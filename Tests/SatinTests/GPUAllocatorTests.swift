@testable import Satin
import Metal
import XCTest

final class GPUAllocatorTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    /// Every class's heaps fixed at `growth` bytes, for tests about reuse, growth and budgets.
    private func allocator(growth: Int = 4 << 20, dedicated: Int? = nil, budget: Int? = nil) -> GPUAllocator {
        var configuration = GPUAllocator.Configuration()
        let fixed = GPUAllocator.HeapSizing(minimumSize: growth, maximumSize: growth)
        configuration.gpuOnly = fixed
        configuration.cpuWrites = fixed
        configuration.cpuReads = fixed
        configuration.dedicatedThreshold = dedicated
        configuration.heapBudget = budget
        return GPUAllocator(device: device, configuration: configuration)
    }

    private func image(width: Int, height: Int, format: MTLPixelFormat) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        return descriptor
    }

    /// 256 KB at rgba8.
    private func descriptor(size: Int = 256, storage: MTLStorageMode = .private,
                            cache: MTLCPUCacheMode = .defaultCache) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = storage
        descriptor.cpuCacheMode = cache
        return descriptor
    }

    func testEachMemoryClassGetsItsOwnHeaps() throws {
        let allocator = allocator()
        let gpuOnly = try allocator.makeTexture(descriptor())
        let cpuWrites = try allocator.makeTexture(descriptor(storage: .shared, cache: .writeCombined))
        let cpuReads = try allocator.makeBuffer(length: 4096, memoryClass: .cpuReads)

        XCTAssertNotNil(gpuOnly.heap)
        XCTAssertNotNil(cpuWrites.heap)
        XCTAssertNotNil(cpuReads.heap)
        XCTAssertEqual(gpuOnly.heap?.storageMode, .private)
        XCTAssertEqual(cpuWrites.heap?.cpuCacheMode, .writeCombined)
        XCTAssertEqual(cpuReads.heap?.storageMode, .shared)
        for memoryClass in GPUAllocator.MemoryClass.allCases {
            XCTAssertEqual(allocator.statistics(for: memoryClass).heapCount, 1, "\(memoryClass)")
        }
    }

    func testTexturesAndBuffersOfOneClassShareItsHeaps() throws {
        let allocator = allocator()
        let texture = try allocator.makeTexture(descriptor(storage: .shared))
        let buffer = try allocator.makeBuffer(length: 4096, memoryClass: .cpuReads)
        XCTAssertTrue(texture.heap === buffer.heap)
        XCTAssertEqual(allocator.statistics(for: .cpuReads).heapCount, 1)
    }

    func testReleasedMemoryIsReusedWithoutNewHeaps() throws {
        let allocator = allocator(growth: 4 << 20)
        // 50 × 256 KB would need ~3 heaps if nothing were reused.
        for _ in 0 ..< 50 {
            _ = try allocator.makeTexture(descriptor())
        }
        let statistics = allocator.statistics(for: .gpuOnly)
        XCTAssertEqual(statistics.heapCount, 1)
        XCTAssertEqual(statistics.usedBytes, 0)
        XCTAssertEqual(statistics.fallbackCount, 0)
    }

    func testLiveAllocationsGrowIntoMoreHeaps() throws {
        let allocator = allocator(growth: 1 << 20)
        let textures = try (0 ..< 8).map { _ in try allocator.makeTexture(descriptor()) }
        XCTAssertEqual(textures.count, 8)
        XCTAssertGreaterThan(allocator.statistics(for: .gpuOnly).heapCount, 1)
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).fallbackCount, 0)
    }

    func testLargeRequestsGetDedicatedAllocations() throws {
        let allocator = allocator(dedicated: 1 << 20)
        let texture = try allocator.makeTexture(descriptor(size: 1024))
        XCTAssertNil(texture.heap)
        let statistics = allocator.statistics(for: .gpuOnly)
        XCTAssertEqual(statistics.dedicatedCount, 1)
        XCTAssertEqual(statistics.heapCount, 0)
    }

    func testRequestsPastTheBudgetFallBackToTheDevice() throws {
        let allocator = allocator(growth: 1 << 20, budget: 1 << 20)
        let textures = try (0 ..< 8).map { _ in try allocator.makeTexture(descriptor()) }
        XCTAssertEqual(textures.count, 8)
        let statistics = allocator.statistics(for: .gpuOnly)
        XCTAssertEqual(statistics.heapCount, 1)
        XCTAssertGreaterThan(statistics.fallbackCount, 0)
        XCTAssertTrue(textures.contains { $0.heap == nil })
    }

    func testTrimReleasesOnlyEmptyHeapsAndKeepsOneSpare() throws {
        let allocator = allocator(growth: 1 << 20)
        var textures = try (0 ..< 12).map { _ in try allocator.makeTexture(descriptor()) }
        let grownHeapCount = allocator.statistics(for: .gpuOnly).heapCount
        XCTAssertGreaterThan(grownHeapCount, 2)

        let survivor = textures[0]
        textures.removeAll()
        allocator.trim()

        let statistics = allocator.statistics(for: .gpuOnly)
        XCTAssertEqual(statistics.heapCount, 2, "the survivor's heap, plus one empty spare")
        XCTAssertGreaterThan(statistics.usedBytes, 0)
        XCTAssertNotNil(survivor.heap)
    }

    func testTrimCanReleaseEveryEmptyHeap() throws {
        let allocator = allocator(growth: 1 << 20)
        var textures = try (0 ..< 12).map { _ in try allocator.makeTexture(descriptor()) }
        XCTAssertGreaterThan(allocator.statistics(for: .gpuOnly).heapCount, 1)
        textures.removeAll()
        allocator.trim(retainingEmptyHeaps: 0)
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).heapCount, 0)
    }

    func testPrivateTexturesIgnoreTheirRequestedCacheMode() throws {
        let allocator = allocator()
        let texture = try allocator.makeTexture(descriptor(storage: .private, cache: .writeCombined))
        XCTAssertEqual(texture.heap?.storageMode, .private)
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).fallbackCount, 0)
    }

    func testLabelsApplyToHeapAndDeviceAllocations() throws {
        let allocator = allocator(dedicated: 1 << 20)
        XCTAssertEqual(try allocator.makeTexture(descriptor(), label: "Heap Texture").label, "Heap Texture")
        XCTAssertEqual(try allocator.makeTexture(descriptor(size: 1024), label: "Dedicated").label, "Dedicated")
        XCTAssertEqual(try allocator.makeBuffer(length: 64, memoryClass: .cpuWrites, label: "Buffer").label, "Buffer")
    }

    // MARK: - Default heap sizing

    func testFullResolution4KImagesShareRequestSizedHeaps() throws {
        for format in [MTLPixelFormat.bgra8Unorm, .rgba16Float] {
            let allocator = GPUAllocator(device: device)
            let descriptor = image(width: 3840, height: 2160, format: format)
            let size = device.heapTextureSizeAndAlign(descriptor: descriptor).size
            let first = try allocator.makeTexture(descriptor)
            let heap = try XCTUnwrap(first.heap, "\(format): a 4K image comes from a heap, not the device")
            XCTAssertGreaterThanOrEqual(heap.size, allocator.configuration.requestsPerHeap * size, "\(format)")
            // Released and reallocated, as a node's output is every frame.
            for _ in 0 ..< 10 { _ = try allocator.makeTexture(descriptor) }
            let statistics = allocator.statistics(for: .gpuOnly)
            XCTAssertEqual(statistics.dedicatedCount, 0, "\(format)")
            XCTAssertEqual(statistics.fallbackCount, 0, "\(format)")
            XCTAssertEqual(statistics.heapCount, 1, "\(format): one heap, reused every frame")
        }
    }

    func testEightLive4KImagesFitTheFirstHeap() throws {
        let allocator = GPUAllocator(device: device)
        let descriptor = image(width: 3840, height: 2160, format: .bgra8Unorm)
        let live = try (0 ..< 8).map { _ in try allocator.makeTexture(descriptor) }
        XCTAssertTrue(live.allSatisfy { $0.heap === live[0].heap })
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).heapCount, 1)
    }

    func testSmallRequestsGetTheClassMinimum() throws {
        let allocator = GPUAllocator(device: device)
        _ = try allocator.makeBuffer(length: 256 << 10, memoryClass: .cpuWrites)
        _ = try allocator.makeTexture(descriptor())
        XCTAssertEqual(allocator.statistics(for: .cpuWrites).heapBytes, allocator.configuration.cpuWrites.minimumSize)
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).heapBytes, allocator.configuration.gpuOnly.minimumSize)
    }

    func testHeapsDoubleUpToTheClassMaximum() throws {
        var configuration = GPUAllocator.Configuration()
        configuration.gpuOnly = GPUAllocator.HeapSizing(minimumSize: 1 << 20, maximumSize: 4 << 20)
        configuration.requestsPerHeap = 1
        let allocator = GPUAllocator(device: device, configuration: configuration)
        // Live 256 KB textures fill each heap in turn, so every new heap shows up once.
        var live: [MTLTexture] = []
        var heapSizes: [Int] = []
        var currentHeap: MTLHeap?
        while heapSizes.count < 4 {
            let texture = try allocator.makeTexture(descriptor())
            live.append(texture)
            let heap = try XCTUnwrap(texture.heap)
            if heap !== currentHeap {
                heapSizes.append(heap.size)
                currentHeap = heap
            }
        }
        withExtendedLifetime(live) {}
        XCTAssertEqual(heapSizes, [1 << 20, 2 << 20, 4 << 20, 4 << 20])
    }

    func testAnInitialSizeSetsTheFirstHeap() throws {
        var configuration = GPUAllocator.Configuration()
        configuration.gpuOnly.initialSize = 96 << 20
        let allocator = GPUAllocator(device: device, configuration: configuration)
        _ = try allocator.makeTexture(descriptor())
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).heapBytes, 96 << 20)
    }

    func testARequestLargerThanTheMaximumStillGetsAHeap() throws {
        var configuration = GPUAllocator.Configuration()
        configuration.gpuOnly = GPUAllocator.HeapSizing(minimumSize: 1 << 20, maximumSize: 1 << 20)
        let allocator = GPUAllocator(device: device, configuration: configuration)
        let texture = try allocator.makeTexture(descriptor(size: 1024))
        XCTAssertNotNil(texture.heap)
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).dedicatedCount, 0)
    }

    func testAClassTrimmedToNothingStartsOverFromItsMinimum() throws {
        let allocator = GPUAllocator(device: device)
        do { _ = try allocator.makeTexture(image(width: 3840, height: 2160, format: .bgra8Unorm)) }
        allocator.trim(retainingEmptyHeaps: 0)
        _ = try allocator.makeTexture(descriptor())
        XCTAssertEqual(allocator.statistics(for: .gpuOnly).heapBytes, allocator.configuration.gpuOnly.minimumSize)
    }
}
