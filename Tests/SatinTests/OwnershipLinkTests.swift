@testable import Satin
import Combine
import Metal
import XCTest

/// Back links (a child's parent and containers, and the subscriptions meshes, materials, posed
/// geometries and parameter groups hold on their sources) are `unowned`: no side table on the
/// objects a frame retains most. They are only safe while each link is cleared before its target
/// goes, so these check every way a target can go while the other side lives on.
final class OwnershipLinkTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    // MARK: - Parents

    func testAChildOutlivingItsParentHasNoParent() {
        let child = Object(context: context, label: "Child")
        weak var released: Object?
        autoreleasepool {
            let parent = Object(context: context, label: "Parent")
            parent.add(child)
            released = parent
            XCTAssertTrue(child.parent === parent)
        }
        XCTAssertNil(released)
        XCTAssertNil(child.parent, "the parent clears the link as it goes")
        XCTAssertEqual(child.worldMatrix, child.localMatrix, "and the child reads its world matrix without it")
    }

    func testAssigningChildrenClearsTheParentOfEachRemovedChild() {
        let parent = Object(context: context, label: "Parent")
        let kept = Object(context: context, label: "Kept")
        let removed = Object(context: context, label: "Removed")
        parent.add(kept)
        parent.add(removed)

        parent.children = [kept]

        XCTAssertTrue(kept.parent === parent)
        XCTAssertNil(removed.parent, "a child no longer in its parent's children has no parent")
    }

    func testAChildRemovedByAssignmentOutlivesItsFormerParent() {
        let child = Object(context: context, label: "Child")
        autoreleasepool {
            let parent = Object(context: context, label: "Parent")
            parent.add(child)
            parent.children = []
        }
        XCTAssertNil(child.parent)
        child.position = [1, 0, 0]
        XCTAssertEqual(child.worldPosition, [1, 0, 0])
    }

    func testAChildMovedToAnotherParentKeepsItsNewParentWhenTheOldOneGoes() {
        let child = Object(context: context, label: "Child")
        let newParent = Object(context: context, label: "New Parent")
        autoreleasepool {
            let oldParent = Object(context: context, label: "Old Parent")
            oldParent.add(child)
            newParent.add(child)
        }
        XCTAssertTrue(child.parent === newParent)
    }

    func testADecodedChildOutlivingItsParentHasNoParent() throws {
        let original = Object(context: context, label: "Parent", [Object(context: context, label: "Child")])
        let data = try JSONEncoder().encode(original)
        var child: Object?
        try autoreleasepool {
            let decoder = JSONDecoder()
            decoder.userInfo[.satinContext] = context
            let decoded = try decoder.decode(Object.self, from: data)
            child = decoded.children.first
            XCTAssertTrue(child?.parent === decoded)
        }
        XCTAssertNil(try XCTUnwrap(child).parent)
    }

    // MARK: - Containers

    func testAContainerOutlivedByItsChildNoLongerHearsOfItsChanges() {
        let child = Object(context: context, label: "Child")
        let parent = Object(context: context, label: "Parent")
        parent.add(child)
        weak var released: Object?
        autoreleasepool {
            let container = Object(context: context, label: "Container")
            container.attach(child)
            released = container
        }
        XCTAssertNil(released)

        let revision = parent.structureRevision
        child.add(Object(context: context, label: "Grandchild"))
        XCTAssertEqual(parent.structureRevision, revision + 1, "the remaining container still hears of changes")
    }

    func testAChildAttachedTwiceAndRemovedOnceStaysContained() {
        let child = Object(context: context, label: "Child")
        let container = Object(context: context, label: "Container")
        container.children = [child, child]
        container.remove(child)

        let revision = container.structureRevision
        child.add(Object(context: context, label: "Grandchild"))
        XCTAssertEqual(container.structureRevision, revision + 1, "one occurrence remains, so it still contains the child")
    }

    // MARK: - Material texture bindings

    func testNamedTexturesFollowGenericBindingReplacementAndRemoval() throws {
        try checkTextureBinding(SsaoCompositeMaterial(context: context), property: \.colorTexture, index: .Custom0)
        try checkTextureBinding(MotionBlurMaterial(context: context), property: \.depthTexture, index: .Custom3)
        try checkTextureBinding(ARPostMaterial(context: context), property: \.cameraGrainTexture, index: .Custom1)
    }

    func testNamedTextureIsRetainedOnlyUntilItsBindingIsCleared() throws {
        let material = SsaoCompositeMaterial(context: context)
        weak var retainedTexture: MTLTexture?
        try autoreleasepool {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
            let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
            retainedTexture = texture
            material.colorTexture = texture
        }
        XCTAssertNotNil(retainedTexture, "The binding owns its texture after the caller releases it")
        autoreleasepool {
            material.set(nil as MTLTexture?, index: FragmentTextureIndex.Custom0)
        }
        XCTAssertNil(retainedTexture, "The named property must not keep a second owner")
        XCTAssertNil(material.colorTexture, "Reading after release must be safe")
    }

    private func checkTextureBinding<MaterialType: Material>(_ material: MaterialType,
        property: ReferenceWritableKeyPath<MaterialType, MTLTexture?>, index: FragmentTextureIndex) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        let original = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let replacement = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        material[keyPath: property] = original
        XCTAssertTrue(material[keyPath: property] === original)
        material.set(replacement, index: index)
        XCTAssertTrue(material[keyPath: property] === replacement, "The named property and binding are one value")
        material.set(nil as MTLTexture?, index: index)
        // Keep both textures alive through the assertion: the old unowned alias otherwise traps.
        XCTAssertNil(material[keyPath: property], "Clearing the binding also clears its named property")
        withExtendedLifetime((original, replacement)) {}
    }

    // MARK: - Subscriptions

    func testAGeometryOutlivingItsMeshCanStillChange() {
        let geometry = QuadGeometry(context: context, size: 1)
        autoreleasepool {
            _ = Mesh(context: context, geometry: geometry, material: BasicColorMaterial(context: context))
        }
        geometry.onUpdate.send(geometry)
    }

    func testASourceOutlivingItsPosedGeometryCanStillChange() {
        let source = QuadGeometry(context: context, size: 1)
        autoreleasepool {
            _ = PosedGeometry(source: source)
        }
        source.onUpdate.send(source)
    }

    func testAPosedGeometryCanBeTheLastOwnerOfItsSource() {
        weak var releasedSource: Geometry?
        autoreleasepool {
            // The source goes as the posed geometry releases it, and removes its attributes as it
            // does: the posed geometry must no longer be listening by then.
            let posed = PosedGeometry(source: QuadGeometry(context: context, size: 1))
            releasedSource = posed.source
        }
        XCTAssertNil(releasedSource)
    }

    func testAShaderOutlivingItsMaterialCanStillPublishParameters() throws {
        var shader: Shader?
        autoreleasepool {
            let material = BasicColorMaterial(context: context)
            material.update()
            shader = material.shader
        }
        try XCTUnwrap(shader).parametersPublisher.send(ParameterGroup("Replacement"))
    }

    func testAParameterOutlivingItsGroupCanStillChange() {
        let parameter = FloatParameter("Amount", 0.5)
        autoreleasepool {
            _ = ParameterGroup("Group", [parameter])
        }
        parameter.value = 1.0
    }
}
