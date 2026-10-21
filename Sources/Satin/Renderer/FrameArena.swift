//
//  FrameArena.swift
//  Satin
//

import Metal

/// Shared transient GPU storage. A producer lease can record before any command buffer exists.
/// It stays alive through every segment that reads it, and while the producer can append work.
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

    /// The only shared mutable allocation state. Leases do not retain the arena, so dropping an
    /// arena while work is in flight cannot form a retain cycle.
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

        /// Orders this thread's earlier writes to chunks before anything that synchronizes after it.
        func synchronize() { lock.sync {} }

        func recycle(_ chunks: [Chunk]) {
            lock.sync {
                for chunk in chunks {
                    chunk.used = 0
                    freeChunks.append(chunk)
                }
            }
        }
    }

    /// Allocation is producer-only. Completion handlers only release
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

        func retain(untilCompleted commandBuffer: MTLCommandBuffer) {
            guard let contents else { preconditionFailure("Recording has finished") }
            let hold = CompletionHold(contents)
            let pool = contents.pool
            // The slices were written before this; completion follows commit through the GPU. The
            // pool's lock makes that order explicit before the chunks are recycled.
            pool.synchronize()
            commandBuffer.addCompletedHandler { _ in
                pool.synchronize()
                hold.contents = nil
            }
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

    private let pool: Pool
    var chunkCount: Int { pool.chunkCount }

    init(device: MTLDevice, initialChunkLength: Int = 256 * 1024, maximumChunkLength: Int = 4 * 1024 * 1024, label: String = "Satin Frame Arena") {
        pool = Pool(device: device, initialChunkLength: initialChunkLength, maximumChunkLength: maximumChunkLength, label: label)
    }

    func lease(frame: FrameTime) -> Lease {
        Lease(pool: pool, frame: frame)
    }
}
