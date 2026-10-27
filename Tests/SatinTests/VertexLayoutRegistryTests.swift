@testable import Satin
import Metal
import XCTest

/// Vertex layouts are interned by value into small integers, so pipeline lookups key by an integer:
/// equal layouts share an ID, different layouts don't, and asking about the same descriptor object
/// again doesn't re-intern it.
final class VertexLayoutRegistryTests: XCTestCase {
    private func makeDescriptor(stride: Int) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.layouts[0].stride = stride
        return descriptor
    }

    func testEqualLayoutsShareAnIDAndDifferentLayoutsDont() {
        let first = VertexLayoutRegistry.layoutID(for: makeDescriptor(stride: 16))
        let equal = VertexLayoutRegistry.layoutID(for: makeDescriptor(stride: 16))
        let different = VertexLayoutRegistry.layoutID(for: makeDescriptor(stride: 32))

        XCTAssertEqual(first, equal)
        XCTAssertNotEqual(first, different)
    }

    func testEditingADescriptorAfterInterningLeavesTheTableIntact() {
        let descriptor = makeDescriptor(stride: 48)
        let original = VertexLayoutRegistry.layoutID(for: descriptor)

        descriptor.layouts[0].stride = 64

        XCTAssertEqual(VertexLayoutRegistry.layoutID(for: makeDescriptor(stride: 48)), original)
        XCTAssertNotEqual(VertexLayoutRegistry.layoutID(for: makeDescriptor(stride: 64)), original)
    }

    func testTheSameObjectIsRememberedAndANewObjectIsInterned() {
        var interned = InternedVertexLayout()
        let descriptor = makeDescriptor(stride: 80)

        let first = interned.layoutID(for: descriptor)
        XCTAssertEqual(interned.layoutID(for: descriptor), first)

        let replacement = makeDescriptor(stride: 96)
        XCTAssertNotEqual(interned.layoutID(for: replacement), first)
        XCTAssertEqual(interned.layoutID(for: replacement), VertexLayoutRegistry.layoutID(for: makeDescriptor(stride: 96)))
    }

    func testAMeshDrawLayoutCarriesItsGeometrysLayoutID() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let first = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
        let second = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))

        XCTAssertEqual(first.drawLayout.vertexLayoutID, first.geometry.vertexLayoutID)
        XCTAssertEqual(first.drawLayout.vertexLayoutID, second.drawLayout.vertexLayoutID, "geometries with equal layouts share an ID")
    }
}
