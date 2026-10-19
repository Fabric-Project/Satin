@testable import Satin
import Combine
import Metal
import XCTest

/// Buffers tell every geometry using them about a change, synchronously, through a relay each
/// geometry owns, so buffers never reference a geometry weakly. A geometry stops listening the
/// moment it stops using a buffer, and a buffer that outlives its geometry is safe to change.
final class GeometryBufferObserverTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = VisualTestHarness.makeContext(device: device)
    }

    private func makePositions(extent: Float) -> Float3BufferAttribute {
        Float3BufferAttribute(defaultValue: .zero, data: [.zero, simd_float3(repeating: extent)])
    }

    /// Counts the geometry's update notifications, which a buffer change triggers.
    private final class UpdateCounter {
        private(set) var count = 0
        private var subscription: AnyCancellable?

        init(_ geometry: Geometry) {
            subscription = geometry.onUpdate.sink { [unowned self] _ in self.count += 1 }
        }

        func reset() { count = 0 }
    }

    // MARK: - Gate: invalidation reaches cached ancestors at once

    func testAnAncestorsCachedBoundsSeeADescendantsBufferChangeBeforeAnyUpdate() {
        let positions = makePositions(extent: 1)
        let geometry = Geometry(context: context)
        geometry.addAttribute(positions, for: .Position)
        let mesh = Mesh(context: context, geometry: geometry, material: nil)
        let parent = Object(context: context, label: "Parent", [mesh])

        XCTAssertEqual(parent.worldBounds.max.x, 1, accuracy: 1e-5, "the parent's bounds are cached")

        positions.data = [.zero, simd_float3(repeating: 2)]

        XCTAssertEqual(parent.worldBounds.max.x, 2, accuracy: 1e-5, "the cached bounds are invalidated without an update")
    }

    // MARK: - Lifetime

    func testReplacingAnAttributeStopsNotificationsFromTheOldOne() {
        let geometry = Geometry(context: context)
        let original = makePositions(extent: 1)
        let replacement = makePositions(extent: 1)
        geometry.addAttribute(original, for: .Position)
        geometry.addAttribute(replacement, for: .Position)
        let counter = UpdateCounter(geometry)

        original.data = [.zero, .one]
        XCTAssertEqual(counter.count, 0, "the replaced attribute no longer notifies")
        XCTAssertEqual(original.observerCount, 0)

        replacement.data = [.zero, .one]
        XCTAssertEqual(counter.count, 1)
    }

    func testReplacingTheElementBufferStopsNotificationsFromTheOldOne() {
        let geometry = Geometry(context: context)
        let original = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)
        let replacement = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)
        geometry.setElements(original)
        geometry.setElements(replacement)
        let counter = UpdateCounter(geometry)

        original.updateData(data: nil, count: 0, source: nil)
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(original.observerCount, 0)

        replacement.updateData(data: nil, count: 0, source: nil)
        XCTAssertEqual(counter.count, 1)
    }

    func testAnAttributeSharedByTwoGeometriesNotifiesBoth() {
        let positions = makePositions(extent: 1)
        let first = Geometry(context: context)
        let second = Geometry(context: context)
        first.addAttribute(positions, for: .Position)
        second.addAttribute(positions, for: .Position)
        let firstCounter = UpdateCounter(first)
        let secondCounter = UpdateCounter(second)

        positions.data = [.zero, .one]

        XCTAssertEqual(firstCounter.count, 1)
        XCTAssertEqual(secondCounter.count, 1)
    }

    func testAnInterleavedBufferSharedWithinOneGeometryRegistersOnceAndUntilItsLastAttributeGoes() {
        let geometry = Geometry(context: context)
        let interleaved = InterleavedBuffer(index: .Vertices, data: nil, stride: MemoryLayout<simd_float4>.stride * 2, count: 0, source: nil)
        geometry.addAttribute(Float4InterleavedBufferAttribute(parent: interleaved, offset: 0), for: .Position)
        geometry.addAttribute(Float4InterleavedBufferAttribute(parent: interleaved, offset: MemoryLayout<simd_float4>.stride), for: .Normal)
        XCTAssertEqual(interleaved.observerCount, 1, "two attributes on one buffer register the geometry once")

        let counter = UpdateCounter(geometry)
        geometry.removeAttribute(.Normal)
        counter.reset()
        let vertexData = UnsafeMutableRawPointer.allocate(byteCount: interleaved.stride, alignment: MemoryLayout<simd_float4>.alignment)
        defer { vertexData.deallocate() }
        interleaved.updateData(data: vertexData, stride: interleaved.stride, count: 0, source: nil)
        XCTAssertEqual(counter.count, 1, "the position attribute still uses the buffer")

        geometry.removeAttribute(.Position)
        XCTAssertEqual(interleaved.observerCount, 0, "the last attribute's removal unregisters the geometry")
    }

    func testABufferOutlivingItsGeometryHoldsNoObserverAndIsSafeToChange() {
        let positions = makePositions(extent: 1)
        let elements = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)
        weak var releasedGeometry: Geometry?
        do {
            let geometry = Geometry(context: context)
            geometry.addAttribute(positions, for: .Position)
            geometry.setElements(elements)
            releasedGeometry = geometry
        }
        XCTAssertNil(releasedGeometry, "nothing else keeps the geometry alive")
        XCTAssertEqual(positions.observerCount, 0)
        XCTAssertEqual(elements.observerCount, 0)

        positions.data = [.zero, .one]
        elements.updateData(data: nil, count: 0, source: nil)
    }
}
