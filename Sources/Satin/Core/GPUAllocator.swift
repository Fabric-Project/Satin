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

    /// How big one memory class's heaps are. A new heap is sized from the request that creates it:
    /// room for `Configuration.requestsPerHeap` of that request, and at least double the class's
    /// previous heap, within `minimumSize ... maximumSize`. A request larger than `maximumSize`
    /// still gets a heap, sized to fit it.
    public struct HeapSizing {
        /// The class's first heap, when the workload is known up front (a 4K or 8K renderer, say);
        /// nil sizes it from its first request like any other heap.
        public var initialSize: Int?
        public var minimumSize: Int
        public var maximumSize: Int

        public init(initialSize: Int? = nil, minimumSize: Int, maximumSize: Int) {
            self.initialSize = initialSize
            self.minimumSize = minimumSize
            self.maximumSize = maximumSize
        }
    }

    public struct Configuration {
        /// Images, render targets and shadow maps: 16 MiB at least, so a 4K bgra8 image (32.4 MiB)
        /// first gets a heap of about 260 MiB that holds eight.
        public var gpuOnly = HeapSizing(minimumSize: 16 << 20, maximumSize: 1 << 30)
        /// Frame-arena chunks and streamed data: small requests, so small heaps.
        public var cpuWrites = HeapSizing(minimumSize: 4 << 20, maximumSize: 64 << 20)
        /// Readbacks.
        public var cpuReads = HeapSizing(minimumSize: 4 << 20, maximumSize: 64 << 20)
        /// How many of the request that creates a heap it should hold, so the next ones fit beside it.
        public var requestsPerHeap = 8
        /// Requests above this size get their own device allocation instead of heap space. Off by
        /// default: an image allocated every frame is far cheaper from a heap than from the device.
        public var dedicatedThreshold: Int?
        /// Soft cap on heap bytes across all classes. Past it, requests fall back to the device.
        public var heapBudget: Int?
        /// Empty heaps `trim()` keeps per class, so the next allocation needn't create one.
        public var retainedEmptyHeaps = 1

        public init() {}

        public func sizing(for memoryClass: MemoryClass) -> HeapSizing {
            switch memoryClass {
            case .gpuOnly: return gpuOnly
            case .cpuWrites: return cpuWrites
            case .cpuReads: return cpuReads
            }
        }
    }

    public struct Statistics: Equatable {
        public let heapCount: Int
        public let heapBytes: Int
        public let usedBytes: Int
        /// Device allocations made because a request was larger than `dedicatedThreshold`, when set.
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
    /// The size of each class's most recent heap, which the next one at least doubles; 0 when the
    /// class has no heaps.
    private var lastHeapSizes = [Int](repeating: 0, count: MemoryClass.allCases.count)

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
            if let threshold = configuration.dedicatedThreshold, sizeAndAlign.size > threshold {
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
            if let threshold = configuration.dedicatedThreshold, sizeAndAlign.size > threshold {
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
        let heapSize = Self.alignUp(newHeapSize(for: memoryClass, request: size), to: max(alignment, 1))
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
        lastHeapSizes[memoryClass.rawValue] = heapSize
        return heap
    }

    /// The size of the next heap of `memoryClass`, created for a request of `request` bytes.
    private func newHeapSize(for memoryClass: MemoryClass, request: Int) -> Int {
        let sizing = configuration.sizing(for: memoryClass)
        let previous = lastHeapSizes[memoryClass.rawValue]
        if previous == 0, let initialSize = sizing.initialSize {
            return max(initialSize, request)
        }
        let wanted = max(sizing.minimumSize, previous * 2, configuration.requestsPerHeap * request)
        return max(min(wanted, sizing.maximumSize), request)
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

    /// Releases heaps holding no live allocations, keeping `retainingEmptyHeaps` per class (by
    /// default the configuration's `retainedEmptyHeaps`). Call on memory pressure, or with 0 when the
    /// allocator's owner shuts down. Heaps still holding objects are never released.
    public func trim(retainingEmptyHeaps: Int? = nil) {
        let retained = retainingEmptyHeaps ?? configuration.retainedEmptyHeaps
        lock.sync {
            for index in heaps.indices {
                var keptEmptyHeaps = 0
                heaps[index].removeAll { heap in
                    guard heap.usedSize == 0 else { return false }
                    keptEmptyHeaps += 1
                    return keptEmptyHeaps > retained
                }
                // A class with no heaps left starts over from its first-heap size.
                if heaps[index].isEmpty { lastHeapSizes[index] = 0 }
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
