//
//  FrameArena.swift
//  Satin
//

import Metal

/// Shared transient GPU storage. A producer lease can record before any command buffer exists.
/// It stays alive through every segment that reads it, and while the producer can append work.
/// Immediate callers retain the command-buffer adapter below until they adopt frame leases.
final class FrameArena {
    struct Slice {
        let buffer: MTLBuffer
        let offset: Int
        let length: Int
        var contents: UnsafeMutableRawPointer { buffer.contents() + offset }
    }

    fileprivate final class Chunk {
        let buffer: MTLBuffer
        var used = 0
        var length: Int { buffer.length }
        init(buffer: MTLBuffer) { self.buffer = buffer }
    }

    /// The only shared mutable allocation state. Leases do not retain the arena or its region
    /// table, so dropping an arena with an abandoned command buffer cannot form a retain cycle.
    fileprivate final class Pool {
        private let device: MTLDevice
        private let maximumChunkLength: Int
        private let label: String
        private let lock = UnfairLock()
        private var freeChunks: [Chunk] = []
        private var nextChunkLength: Int
        private var createdChunkCount = 0
        var chunkCount: Int { lock.sync { createdChunkCount } }

        init(device: MTLDevice, initialChunkLength: Int, maximumChunkLength: Int, label: String) {
            self.device = device
            nextChunkLength = initialChunkLength
            self.maximumChunkLength = max(initialChunkLength, maximumChunkLength)
            self.label = label
        }

        func take(minimumLength: Int) -> Chunk {
            lock.sync {
                if let index = freeChunks.firstIndex(where: { $0.length >= minimumLength }) {
                    return freeChunks.remove(at: index)
                }
                let length = max(minimumLength, nextChunkLength)
                nextChunkLength = min(nextChunkLength * 2, maximumChunkLength)
                guard let buffer = device.makeBuffer(length: length, options: [.storageModeShared, .cpuCacheModeWriteCombined]) else {
                    fatalError("\(label): could not allocate a \(length) byte chunk")
                }
                buffer.label = "\(label) Chunk \(createdChunkCount)"
                createdChunkCount += 1
                return Chunk(buffer: buffer)
            }
        }

        func recycle(_ chunks: [Chunk]) {
            lock.sync {
                for chunk in chunks {
                    chunk.used = 0
                    freeChunks.append(chunk)
                }
            }
        }
    }

    /// Allocation and owner registration are producer-only. Completion handlers only release
    /// their hold; they never mutate an active lease. Earlier slices are never overwritten.
    final class Lease {
        let frame: FrameTime
        private var contents: Contents?

        fileprivate init(pool: Pool, frame: FrameTime) {
            self.frame = frame
            contents = Contents(pool: pool)
        }

        func allocate(length: Int, alignment: Int = 256) -> Slice {
            guard let contents else { preconditionFailure("Recording has finished") }
            return contents.allocate(length: length, alignment: alignment)
        }

        func retain(_ owner: AnyObject) {
            guard let contents else { preconditionFailure("Recording has finished") }
            contents.retainedOwners.append(owner)
        }

        func retain(untilCompleted commandBuffer: MTLCommandBuffer) {
            guard let contents else { preconditionFailure("Recording has finished") }
            let hold = CompletionHold(contents)
            commandBuffer.addCompletedHandler { _ in hold.contents = nil }
        }

        /// Transfers the producer's hold to the submitted segments. Retaining a consumed builder
        /// or a completed sealed submission cannot prolong the contents' lifetime.
        func finishRecording() { contents = nil }

        private final class CompletionHold {
            var contents: Contents?
            init(_ contents: Contents) { self.contents = contents }
        }

        private final class Contents {
            let pool: Pool
            var chunks: [Chunk] = []
            var retainedOwners: [AnyObject] = []
            init(pool: Pool) { self.pool = pool }
            deinit { pool.recycle(chunks) }

            func allocate(length: Int, alignment: Int) -> Slice {
                precondition(alignment > 0 && alignment.nonzeroBitCount == 1, "Alignment must be a power of two")
                let length = max(length, 1)
                if let chunk = chunks.last {
                    let offset = (chunk.used + alignment - 1) & ~(alignment - 1)
                    if offset + length <= chunk.length {
                        chunk.used = offset + length
                        return Slice(buffer: chunk.buffer, offset: offset, length: length)
                    }
                }
                let chunk = pool.take(minimumLength: length)
                chunks.append(chunk)
                chunk.used = length
                return Slice(buffer: chunk.buffer, offset: 0, length: length)
            }
        }
    }

    private final class Region {
        weak var commandBuffer: MTLCommandBuffer?
        var lease: Lease?
        var completed = false
        init(commandBuffer: MTLCommandBuffer, lease: Lease) {
            self.commandBuffer = commandBuffer
            self.lease = lease
        }
    }

    private let pool: Pool
    private var activeRegions: [Region] = []
    private let lock = UnfairLock()
    var chunkCount: Int { pool.chunkCount }

    init(device: MTLDevice, initialChunkLength: Int = 256 * 1024, maximumChunkLength: Int = 4 * 1024 * 1024, label: String = "Satin Frame Arena") {
        pool = Pool(device: device, initialChunkLength: initialChunkLength, maximumChunkLength: maximumChunkLength, label: label)
    }

    func lease(frame: FrameTime) -> Lease {
        Lease(pool: pool, frame: frame)
    }

    // MARK: - Immediate compatibility

    /// Allocate before commit. The command buffer owns this adapter region until completion;
    /// an uncommitted command buffer's region is reclaimed on the next allocation.
    func allocate(length: Int, alignment: Int = 256, commandBuffer: MTLCommandBuffer) -> Slice {
        immediateLease(for: commandBuffer).allocate(length: length, alignment: alignment)
    }

    func allocate<Sample>(_ value: Sample, commandBuffer: MTLCommandBuffer) -> Slice {
        var value = value
        let slice = allocate(length: MemoryLayout<Sample>.stride, alignment: max(MemoryLayout<Sample>.alignment, 256), commandBuffer: commandBuffer)
        withUnsafeBytes(of: &value) { bytes in
            if let source = bytes.baseAddress { slice.contents.copyMemory(from: source, byteCount: bytes.count) }
        }
        return slice
    }

    func allocate<Sample>(_ values: UnsafeBufferPointer<Sample>, commandBuffer: MTLCommandBuffer) -> Slice {
        let length = MemoryLayout<Sample>.stride * values.count
        let slice = allocate(length: length, alignment: max(MemoryLayout<Sample>.alignment, 256), commandBuffer: commandBuffer)
        if let source = values.baseAddress, length > 0 { slice.contents.copyMemory(from: source, byteCount: length) }
        return slice
    }

    func retainUntilCompleted(_ owner: AnyObject, commandBuffer: MTLCommandBuffer) {
        immediateLease(for: commandBuffer).retain(owner)
    }

    private func immediateLease(for commandBuffer: MTLCommandBuffer) -> Lease {
        if let region = activeRegions.last, region.commandBuffer === commandBuffer, let lease = region.lease { return lease }
        for region in activeRegions where region.commandBuffer === commandBuffer {
            if let lease = region.lease { return lease }
            preconditionFailure("Cannot allocate after command-buffer completion")
        }
        reclaimFinishedRegions()
        let lease = lease(frame: .zero)
        let region = Region(commandBuffer: commandBuffer, lease: lease)
        activeRegions.append(region)
        commandBuffer.addCompletedHandler { _ in
            let released: Lease? = self.lock.sync {
                region.completed = true
                let lease = region.lease
                region.lease = nil
                return lease
            }
            withExtendedLifetime(released) {}
        }
        return lease
    }

    private func reclaimFinishedRegions() {
        var released: [Region] = []
        lock.sync {
            activeRegions.removeAll { region in
                guard region.completed || region.commandBuffer == nil else { return false }
                released.append(region)
                return true
            }
        }
        // Releasing an abandoned region can run arbitrary owner deinits.
        released.removeAll()
    }
}
