import Metal

/// Device memory for textures and buffers that may outlive a frame: images, shadow maps, results
/// handed to other owners. Each call returns a new object placed in a shared heap. Its memory returns
/// to that heap when its last owner (a CPU reference or a command buffer using it) releases it, so an
/// object may escape to any owner safely. Objects are never pooled or reissued.
///
/// Heaps are created lazily, grouped by memory class, and shared by every context given the same
/// allocator. Requests the heaps can't serve fall back to ordinary device allocations, which are
/// counted in `statistics(for:)` so a misconfiguration is visible rather than fatal.
public final class GPUAllocator {
    /// Where an allocation lives and who touches it. Each class has its own heaps, because a heap
    /// has a single storage and CPU cache mode.
    public enum MemoryClass: Int, CaseIterable {
        /// Private storage: render targets, shadow maps, compute outputs.
        case gpuOnly
        /// Shared, write-combined: data the CPU writes and the GPU reads, such as streamed geometry.
        case cpuWrites
        /// Shared, default cache: data the CPU reads back.
        case cpuReads

        var storageMode: MTLStorageMode { self == .gpuOnly ? .private : .shared }
        var cpuCacheMode: MTLCPUCacheMode { self == .cpuWrites ? .writeCombined : .defaultCache }
        var resourceOptions: MTLResourceOptions {
            switch self {
            case .gpuOnly: return [.storageModePrivate, .hazardTrackingModeTracked]
            case .cpuWrites: return [.storageModeShared, .cpuCacheModeWriteCombined, .hazardTrackingModeTracked]
            case .cpuReads: return [.storageModeShared, .hazardTrackingModeTracked]
            }
        }

        /// The class serving a texture descriptor; nil for modes heaps don't hold (memoryless, managed).
        init?(storageMode: MTLStorageMode, cpuCacheMode: MTLCPUCacheMode) {
            switch storageMode {
            case .private: self = .gpuOnly
            case .shared: self = cpuCacheMode == .writeCombined ? .cpuWrites : .cpuReads
            default: return nil
            }
        }
    }

    public struct Configuration {
        /// Bytes per new heap; a request larger than half of this gets a heap twice its size.
        public var heapGrowthSize = 64 << 20
        /// Requests above this size get their own device allocation instead of heap space.
        public var dedicatedThreshold = 32 << 20
        /// Soft cap on heap bytes across all classes. Past it, requests fall back to the device.
        public var heapBudget: Int?
        /// Empty heaps `trim()` keeps per class, so the next allocation needn't create one.
        public var retainedEmptyHeaps = 1

        public init() {}
    }

    public struct Statistics: Equatable {
        public let heapCount: Int
        public let heapBytes: Int
        public let usedBytes: Int
        /// Device allocations made because a request was larger than `dedicatedThreshold`.
        public let dedicatedCount: Int
        /// Device allocations made because the heaps couldn't serve a request (budget, mode, failure).
        public let fallbackCount: Int
    }

    public let device: MTLDevice
    public let configuration: Configuration

    private let lock = UnfairLock()
    private var heaps: [ContiguousArray<MTLHeap>] = Array(repeating: [], count: MemoryClass.allCases.count)
    private var dedicatedCounts = [Int](repeating: 0, count: MemoryClass.allCases.count)
    private var fallbackCounts = [Int](repeating: 0, count: MemoryClass.allCases.count)
    private var createdHeapCount = 0

    public init(device: MTLDevice, configuration: Configuration = .init()) {
        self.device = device
        self.configuration = configuration
    }

    // MARK: - Allocation

    public func makeTexture(_ descriptor: MTLTextureDescriptor, label: String? = nil) throws -> MTLTexture {
        // Memoryless and managed textures can't live in heaps; they are ordinary device allocations.
        guard let memoryClass = MemoryClass(storageMode: descriptor.storageMode, cpuCacheMode: descriptor.cpuCacheMode) else {
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw GPUError.allocationFailed }
            if let label { texture.label = label }
            return texture
        }
        // A private texture's CPU cache mode is meaningless, but must match its heap's.
        var descriptor = descriptor
        if memoryClass == .gpuOnly, descriptor.cpuCacheMode != .defaultCache,
           let normalized = descriptor.copy() as? MTLTextureDescriptor {
            normalized.cpuCacheMode = .defaultCache
            descriptor = normalized
        }
        let texture: MTLTexture? = lock.sync {
            let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
            if sizeAndAlign.size > configuration.dedicatedThreshold {
                dedicatedCounts[memoryClass.rawValue] += 1
                return device.makeTexture(descriptor: descriptor)
            }
            if let heap = heap(for: memoryClass, size: sizeAndAlign.size, alignment: sizeAndAlign.align),
               let texture = heap.makeTexture(descriptor: descriptor) {
                return texture
            }
            fallbackCounts[memoryClass.rawValue] += 1
            return device.makeTexture(descriptor: descriptor)
        }
        guard let texture else { throw GPUError.allocationFailed }
        if let label { texture.label = label }
        return texture
    }

    public func makeBuffer(length: Int, memoryClass: MemoryClass, label: String? = nil) throws -> MTLBuffer {
        let options = memoryClass.resourceOptions
        let buffer: MTLBuffer? = lock.sync {
            let sizeAndAlign = device.heapBufferSizeAndAlign(length: length, options: options)
            if sizeAndAlign.size > configuration.dedicatedThreshold {
                dedicatedCounts[memoryClass.rawValue] += 1
                return device.makeBuffer(length: length, options: options)
            }
            if let heap = heap(for: memoryClass, size: sizeAndAlign.size, alignment: sizeAndAlign.align),
               let buffer = heap.makeBuffer(length: length, options: options) {
                return buffer
            }
            fallbackCounts[memoryClass.rawValue] += 1
            return device.makeBuffer(length: length, options: options)
        }
        guard let buffer else { throw GPUError.allocationFailed }
        if let label { buffer.label = label }
        return buffer
    }

    /// A heap of `memoryClass` with room for `size` bytes at `alignment`: an existing one first,
    /// else a new one within budget. Called with the lock held.
    private func heap(for memoryClass: MemoryClass, size: Int, alignment: Int) -> MTLHeap? {
        for heap in heaps[memoryClass.rawValue] where heap.maxAvailableSize(alignment: alignment) >= size {
            return heap
        }
        let heapSize = Self.alignUp(max(configuration.heapGrowthSize, size * 2), to: max(alignment, 1))
        if let budget = configuration.heapBudget, totalHeapBytes() + heapSize > budget { return nil }

        let descriptor = MTLHeapDescriptor()
        descriptor.type = .automatic
        descriptor.size = heapSize
        descriptor.storageMode = memoryClass.storageMode
        descriptor.cpuCacheMode = memoryClass.cpuCacheMode
        descriptor.hazardTrackingMode = .tracked
        guard let heap = device.makeHeap(descriptor: descriptor) else { return nil }
        createdHeapCount += 1
        heap.label = "Satin GPUAllocator \(memoryClass) Heap \(createdHeapCount)"
        heaps[memoryClass.rawValue].append(heap)
        return heap
    }

    private func totalHeapBytes() -> Int {
        var total = 0
        for classHeaps in heaps {
            for heap in classHeaps { total += heap.size }
        }
        return total
    }

    private static func alignUp(_ value: Int, to alignment: Int) -> Int {
        (value + alignment - 1) / alignment * alignment
    }

    // MARK: - Maintenance

    /// Releases heaps holding no live allocations, keeping `retainedEmptyHeaps` per class. Call on
    /// memory pressure or when a document closes. Heaps still holding objects are never released.
    public func trim() {
        lock.sync {
            for index in heaps.indices {
                var keptEmptyHeaps = 0
                heaps[index].removeAll { heap in
                    guard heap.usedSize == 0 else { return false }
                    keptEmptyHeaps += 1
                    return keptEmptyHeaps > configuration.retainedEmptyHeaps
                }
            }
        }
    }

    public func statistics(for memoryClass: MemoryClass) -> Statistics {
        lock.sync {
            var heapBytes = 0
            var usedBytes = 0
            for heap in heaps[memoryClass.rawValue] {
                heapBytes += heap.size
                usedBytes += heap.usedSize
            }
            return Statistics(heapCount: heaps[memoryClass.rawValue].count,
                              heapBytes: heapBytes,
                              usedBytes: usedBytes,
                              dedicatedCount: dedicatedCounts[memoryClass.rawValue],
                              fallbackCount: fallbackCounts[memoryClass.rawValue])
        }
    }
}
