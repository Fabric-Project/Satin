//
//  FrameArena.swift
//  Satin
//

import Metal

/// Transient GPU storage for the work one command buffer carries: per-draw uniforms, instance and
/// joint matrices, CPU-mutable geometry and GPU preparation outputs. Every allocation made for a
/// command buffer stays valid, and its bytes untouched, until that command buffer completes.
///
/// Storage comes from chunks of shared, write-combined buffers. A region holds the chunks one
/// command buffer uses, from its first allocation to its completion: growing takes another chunk,
/// so earlier slices are never moved or invalidated. Completed regions return their chunks for
/// reuse, so a steady workload allocates nothing. A command buffer released without ever being
/// committed never completes; its region is reclaimed the next time the arena allocates.
///
/// Allocate only before the command buffer is committed: the arena registers its completion
/// handler on the first allocation.
final class FrameArena {
    /// A range of one chunk, valid with the command buffer it was allocated for until it completes.
    struct Slice {
        let buffer: MTLBuffer
        let offset: Int
        let length: Int

        var contents: UnsafeMutableRawPointer { buffer.contents() + offset }
    }

    private final class Chunk {
        let buffer: MTLBuffer
        var used = 0

        init(buffer: MTLBuffer) {
            self.buffer = buffer
        }

        var length: Int { buffer.length }
    }

    private final class Region {
        weak var commandBuffer: MTLCommandBuffer?
        /// The chunks this region allocates from, the last one current.
        var chunks: [Chunk] = []
        /// Objects kept alive until the command buffer completes.
        var retainedOwners: [AnyObject] = []
        /// Set from the command buffer's completed handler.
        var completed = false

        init(commandBuffer: MTLCommandBuffer) {
            self.commandBuffer = commandBuffer
        }
    }

    private let device: MTLDevice
    private let initialChunkLength: Int
    private let maximumChunkLength: Int
    private let label: String

    /// Regions whose command buffers have not completed or been reclaimed. A handful at most,
    /// one per command buffer in flight, so they are found by comparing identities in turn.
    private var activeRegions: [Region] = []
    /// Chunks no region holds, ready for reuse. Guarded by `lock`: completed handlers return
    /// chunks from Metal's completion thread.
    private var freeChunks: [Chunk] = []
    private var nextChunkLength: Int
    private let lock = UnfairLock()

    /// Every chunk this arena has created, in use or free.
    private(set) var chunkCount = 0

    init(
        device: MTLDevice,
        initialChunkLength: Int = 256 * 1024,
        maximumChunkLength: Int = 4 * 1024 * 1024,
        label: String = "Satin Frame Arena"
    ) {
        self.device = device
        self.initialChunkLength = initialChunkLength
        self.maximumChunkLength = max(initialChunkLength, maximumChunkLength)
        self.nextChunkLength = initialChunkLength
        self.label = label
    }

    // MARK: - Allocation

    /// `length` bytes aligned to `alignment` (a power of two), valid until `commandBuffer` completes.
    func allocate(length: Int, alignment: Int = 256, commandBuffer: MTLCommandBuffer) -> Slice {
        let length = max(length, 1)
        let region = region(for: commandBuffer)

        if let chunk = region.chunks.last {
            let offset = align(chunk.used, to: alignment)
            if offset + length <= chunk.length {
                chunk.used = offset + length
                return Slice(buffer: chunk.buffer, offset: offset, length: length)
            }
        }

        let chunk = takeChunk(minimumLength: length)
        region.chunks.append(chunk)
        chunk.used = length
        return Slice(buffer: chunk.buffer, offset: 0, length: length)
    }

    /// A slice holding a copy of `value`.
    func allocate<T>(_ value: T, commandBuffer: MTLCommandBuffer) -> Slice {
        var value = value
        let slice = allocate(length: MemoryLayout<T>.stride, alignment: max(MemoryLayout<T>.alignment, 256), commandBuffer: commandBuffer)
        withUnsafeBytes(of: &value) { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            slice.contents.copyMemory(from: baseAddress, byteCount: bytes.count)
        }
        return slice
    }

    /// A slice holding a copy of `values`, laid out at their stride.
    func allocate<T>(_ values: UnsafeBufferPointer<T>, commandBuffer: MTLCommandBuffer) -> Slice {
        let length = MemoryLayout<T>.stride * values.count
        let slice = allocate(length: length, alignment: max(MemoryLayout<T>.alignment, 256), commandBuffer: commandBuffer)
        if let baseAddress = values.baseAddress, length > 0 {
            slice.contents.copyMemory(from: baseAddress, byteCount: length)
        }
        return slice
    }

    // MARK: - Lifetime

    /// Keeps `owner` alive until `commandBuffer` completes, or until its region is reclaimed if the
    /// command buffer is never committed.
    func retainUntilCompleted(_ owner: AnyObject, commandBuffer: MTLCommandBuffer) {
        let region = region(for: commandBuffer)
        lock.sync {
            region.retainedOwners.append(owner)
        }
    }

    private func region(for commandBuffer: MTLCommandBuffer) -> Region {
        if let region = activeRegions.last, region.commandBuffer === commandBuffer {
            return region
        }
        for region in activeRegions where region.commandBuffer === commandBuffer {
            return region
        }

        reclaimFinishedRegions()

        let region = Region(commandBuffer: commandBuffer)
        activeRegions.append(region)
        // Strong: the arena outlives the command buffers it allocates for, and needs no side table.
        // The handler is released with the command buffer, completed or not, so this is no cycle.
        commandBuffer.addCompletedHandler { _ in
            self.complete(region)
        }
        return region
    }

    /// Runs on Metal's completion thread.
    private func complete(_ region: Region) {
        let owners: [AnyObject] = lock.sync {
            region.completed = true
            returnChunks(of: region)
            let owners = region.retainedOwners
            region.retainedOwners.removeAll()
            return owners
        }
        // Released outside the lock: an owner's deinit may do arbitrary work.
        _ = owners
    }

    /// Drops completed regions, and reclaims regions whose command buffer was released without
    /// completing, which means it was never committed.
    private func reclaimFinishedRegions() {
        var abandonedOwners: [AnyObject] = []
        lock.sync {
            activeRegions.removeAll { region in
                if region.completed { return true }
                guard region.commandBuffer == nil else { return false }
                returnChunks(of: region)
                abandonedOwners.append(contentsOf: region.retainedOwners)
                region.retainedOwners.removeAll()
                return true
            }
        }
        abandonedOwners.removeAll()
    }

    /// Called with `lock` held.
    private func returnChunks(of region: Region) {
        for chunk in region.chunks {
            chunk.used = 0
            freeChunks.append(chunk)
        }
        region.chunks.removeAll()
    }

    private func takeChunk(minimumLength: Int) -> Chunk {
        let reused: Chunk? = lock.sync {
            guard let index = freeChunks.firstIndex(where: { $0.length >= minimumLength }) else { return nil }
            return freeChunks.remove(at: index)
        }
        if let reused {
            return reused
        }

        let length = max(minimumLength, nextChunkLength)
        nextChunkLength = min(nextChunkLength * 2, maximumChunkLength)
        guard let buffer = device.makeBuffer(length: length, options: [.storageModeShared, .cpuCacheModeWriteCombined]) else {
            fatalError("\(label): could not allocate a \(length) byte chunk")
        }
        buffer.label = "\(label) Chunk \(chunkCount)"
        chunkCount += 1
        return Chunk(buffer: buffer)
    }

    private func align(_ value: Int, to alignment: Int) -> Int {
        (value + alignment - 1) & ~(alignment - 1)
    }
}
