@testable import Satin
import Metal
import XCTest

final class GPUAllocatorTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func allocator(growth: Int = 4 << 20, dedicated: Int = 32 << 20, budget: Int? = nil) -> GPUAllocator {
        var configuration = GPUAllocator.Configuration()
        configuration.heapGrowthSize = growth
        configuration.dedicatedThreshold = dedicated
        configuration.heapBudget = budget
        return GPUAllocator(device: device, configuration: configuration)
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
}
