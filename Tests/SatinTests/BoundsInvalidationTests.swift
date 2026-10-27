@testable import Satin
import Metal
import simd
import XCTest

/// Bounds marking stops at an already-marked object. These cover the cases where stopping early
/// could leave a cached ancestor stale.
final class BoundsInvalidationTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func makeMesh() -> Mesh {
        Mesh(context: context, geometry: QuadGeometry(context: context, size: 1), material: BasicColorMaterial(context: context))
    }

    func testRepeatedMarksOnADeepLeafReachTheRoot() {
        let leaf = makeMesh()
        let middle = Object(context: context, label: "Middle", [leaf])
        let root = Object(context: context, label: "Root", [Object(context: context, label: "Upper", [middle])])
        XCTAssertEqual(root.worldBounds.max.x, 0.5, accuracy: 0.001)

        leaf.position = [2, 0, 0]
        leaf.position = [5, 0, 0]
        XCTAssertEqual(root.worldBounds.max.x, 5.5, accuracy: 0.001)

        leaf.position = [1, 0, 0]
        XCTAssertEqual(root.worldBounds.max.x, 1.5, accuracy: 0.001)
    }

    func testASiblingMarkedAfterAnotherStillReachesTheRoot() {
        let first = makeMesh()
        let second = makeMesh()
        let root = Object(context: context, label: "Root", [Object(context: context, label: "Parent", [first, second])])
        XCTAssertEqual(root.worldBounds.max.x, 0.5, accuracy: 0.001)

        first.position = [2, 0, 0]
        second.position = [7, 0, 0]

        XCTAssertEqual(root.worldBounds.max.x, 7.5, accuracy: 0.001)
    }

    func testAMarkedChildMovedToANewParentUpdatesIt() {
        let child = makeMesh()
        let oldParent = Object(context: context, label: "Old", [child])
        let newParent = Object(context: context, label: "New")
        XCTAssertEqual(oldParent.worldBounds.max.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(newParent.worldBounds.max.x, createBounds().max.x)

        child.position = [4, 0, 0]
        newParent.add(child)

        XCTAssertEqual(newParent.worldBounds.max.x, 4.5, accuracy: 0.001)
    }

    func testALocalMarkStillMarksWorldBoundsAfterTheyWereRead() {
        let mesh = makeMesh()
        let parent = Object(context: context, label: "Parent", [mesh])
        XCTAssertEqual(parent.worldBounds.max.x, 0.5, accuracy: 0.001)
        XCTAssertTrue(mesh._updateLocalBounds, "World bounds reads leave the local mark set")

        mesh.position = [3, 0, 0]

        XCTAssertEqual(parent.worldBounds.max.x, 3.5, accuracy: 0.001)
        XCTAssertEqual(mesh.localBounds.max.x, 3.5, accuracy: 0.001)
    }
}
