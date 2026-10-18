@testable import Satin
import Metal
import XCTest

/// `SceneIndex` flattens a root's descendants in preorder, one entry per occurrence, cast once. Any
/// structure change below a root, however it is made, advances the root's revision and drops its
/// cached index; an index already built never changes, and an index never keeps its root alive.
final class SceneIndexTests: XCTestCase {
    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func makeMesh(_ context: Context, _ label: String) -> Mesh {
        Mesh(context: context, label: label, geometry: Geometry(context: context), material: BasicColorMaterial(context: context))
    }

    private func labels(_ index: SceneIndex) -> [String] {
        index.entries.map(\.object.label)
    }

    // MARK: - Structure

    func testEntriesArePreorderWithSubtreeEndsAndParents() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let a = Object(context: context, label: "a")
        let a1 = Object(context: context, label: "a1")
        let a2 = Object(context: context, label: "a2")
        let b = Object(context: context, label: "b")
        root.add(a)
        a.add(a1)
        a.add(a2)
        root.add(b)

        let index = root.sceneIndex

        XCTAssertEqual(labels(index), ["a", "a1", "a2", "b"])
        XCTAssertEqual(index.entries.map(\.subtreeEnd), [3, 2, 3, 4])
        XCTAssertEqual(index.entries.map(\.parentEntry), [-1, 0, 0, -1])
    }

    func testTypedViewsMatchTheCasts() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let mesh = makeMesh(context, "mesh")
        let light = DirectionalLight(context: context, color: .one)
        let camera = PerspectiveCamera(context: context)
        root.add(mesh)
        mesh.add(light)
        root.add(camera)

        let index = root.sceneIndex

        XCTAssertEqual(index.renderables.map(\.label), ["mesh"])
        XCTAssertEqual(index.lights.map(\.label), [light.label])
        XCTAssertEqual(index.cameras.map(\.label), [camera.label])
        XCTAssertTrue(index.entries[0].renderable === mesh)
        XCTAssertTrue(index.entries[1].light === light)
        XCTAssertNil(index.entries[2].renderable)
    }

    func testTheRootIsNotIndexed() throws {
        let context = try makeContext()
        let roots: [Object] = [
            Object(context: context, label: "object root"),
            makeMesh(context, "mesh root"),
            DirectionalLight(context: context, color: .one),
        ]

        for root in roots {
            root.add(Object(context: context, label: "child"))
            let index = root.sceneIndex
            XCTAssertEqual(labels(index), ["child"])
            XCTAssertFalse(index.renderables.contains { $0 === root })
            XCTAssertFalse(index.lights.contains { $0 === root })
        }
    }

    func testASharedChildAppearsOncePerOccurrence() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let first = Object(context: context, label: "first")
        let second = Object(context: context, label: "second")
        let shared = Object(context: context, label: "shared")
        root.add(first)
        root.add(second)
        first.add(shared)
        second.attach(shared)

        XCTAssertEqual(labels(root.sceneIndex), ["first", "shared", "second", "shared"])
    }

    func testAnAttachCycleIsSkipped() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let a = Object(context: context, label: "a")
        let b = Object(context: context, label: "b")
        root.add(a)
        a.add(b)
        b.attach(a)

        let index = root.sceneIndex

        XCTAssertEqual(labels(index), ["a", "b"])
        XCTAssertEqual(index.skippedCycles, 1)
    }

    func testADescendantAttachingTheRootIsSkipped() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let a = Object(context: context, label: "a")
        root.add(a)
        a.attach(root)

        let index = root.sceneIndex

        XCTAssertEqual(labels(index), ["a"])
        XCTAssertEqual(index.skippedCycles, 1)
    }

    // MARK: - Snapshots

    func testABuiltIndexNeverChanges() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let a = Object(context: context, label: "a")
        root.add(a)

        let before = root.sceneIndex
        root.add(Object(context: context, label: "b"))
        a.add(Object(context: context, label: "a1"))
        let after = root.sceneIndex

        XCTAssertFalse(before === after)
        XCTAssertEqual(labels(before), ["a"])
        XCTAssertEqual(labels(after), ["a", "a1", "b"])
    }

    func testAnUnchangedSceneReusesItsIndex() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        root.add(Object(context: context, label: "a"))

        XCTAssertTrue(root.sceneIndex === root.sceneIndex)
    }

    // MARK: - Membership and Revision

    private func assertChangeAdvancesRoot(
        _ root: Object,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: () -> Void
    ) {
        let index = root.sceneIndex
        let revision = root.structureRevision
        change()
        XCTAssertEqual(root.structureRevision, revision &+ 1, "one notification per change", file: file, line: line)
        XCTAssertFalse(root.sceneIndex === index, "the next read rebuilds", file: file, line: line)
    }

    func testEveryKindOfChangeAdvancesTheRootOnce() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let child = Object(context: context, label: "child")
        let attached = Object(context: context, label: "attached")

        assertChangeAdvancesRoot(root) { root.add(child) }
        assertChangeAdvancesRoot(root) { root.attach(attached) }
        assertChangeAdvancesRoot(root) { root.insert(Object(context: context, label: "inserted"), at: 0) }
        assertChangeAdvancesRoot(root) { root.insert(Object(context: context, label: "unparented"), at: 0, setParent: false) }
        assertChangeAdvancesRoot(root) { child.add(Object(context: context, label: "grandchild")) }
        assertChangeAdvancesRoot(root) { attached.add(Object(context: context, label: "under attached")) }
        assertChangeAdvancesRoot(root) { root.remove(child) }
        assertChangeAdvancesRoot(root) { root.children = [child] }
        assertChangeAdvancesRoot(root) { root.children.append(attached) }
    }

    func testRemoveAllAdvancesTheRootOncePerChild() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        root.add(Object(context: context, label: "a"))
        root.add(Object(context: context, label: "b"))
        let revision = root.structureRevision

        root.removeAll()

        XCTAssertEqual(root.structureRevision, revision &+ 2)
        XCTAssertTrue(root.sceneIndex.entries.isEmpty)
    }

    func testAChildAssignedDirectlyStillReportsLaterChanges() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let child = Object(context: context, label: "child")
        root.children = [child]
        XCTAssertNil(child.parent, "direct assignment sets no parent")
        _ = root.sceneIndex

        assertChangeAdvancesRoot(root) { child.add(Object(context: context, label: "grandchild")) }
        XCTAssertEqual(labels(root.sceneIndex), ["child", "grandchild"])
    }

    func testRepeatedDescendantChangesAllReachTheRoot() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        let child = Object(context: context, label: "child")
        root.add(child)
        _ = child.sceneIndex
        child.add(Object(context: context, label: "first"))

        // Only the root's index is rebuilt between the changes; the child's stays dropped.
        assertChangeAdvancesRoot(root) { child.add(Object(context: context, label: "second")) }
        assertChangeAdvancesRoot(root) { child.add(Object(context: context, label: "third")) }
    }

    func testAChangeUnderASharedChildAdvancesBothContainers() throws {
        let context = try makeContext()
        let first = Object(context: context, label: "first")
        let second = Object(context: context, label: "second")
        let shared = Object(context: context, label: "shared")
        first.add(shared)
        second.attach(shared)
        let firstRevision = first.structureRevision
        let secondRevision = second.structureRevision

        shared.add(Object(context: context, label: "below"))

        XCTAssertEqual(first.structureRevision, firstRevision &+ 1)
        XCTAssertEqual(second.structureRevision, secondRevision &+ 1)
    }

    func testAChangeIsSeenEvenWhenTheIndexIsRebuiltStraightAway() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        root.add(Object(context: context, label: "a"))
        let revision = root.structureRevision

        root.add(Object(context: context, label: "b"))
        _ = root.sceneIndex

        XCTAssertNotEqual(root.structureRevision, revision)
    }

    func testDecodedChildrenReportChanges() throws {
        let context = try makeContext()
        let original = Object(context: context, label: "root")
        original.add(Object(context: context, label: "child"))

        let data = try JSONEncoder().encode(original)
        let decoder = JSONDecoder()
        decoder.userInfo[.satinContext] = context
        let decoded = try decoder.decode(Object.self, from: data)
        let decodedChild = try XCTUnwrap(decoded.children.first)
        _ = decoded.sceneIndex

        assertChangeAdvancesRoot(decoded) { decodedChild.add(Object(context: context, label: "grandchild")) }
    }

    func testAnAttachCycleChangeTerminates() throws {
        let context = try makeContext()
        let a = Object(context: context, label: "a")
        let b = Object(context: context, label: "b")
        a.add(b)
        b.attach(a)
        let revision = a.structureRevision

        b.add(Object(context: context, label: "c"))

        XCTAssertEqual(a.structureRevision, revision &+ 1)
    }

    func testTransientContainersAreReleasedAndPruned() throws {
        let context = try makeContext()
        let shared = Object(context: context, label: "shared")
        weak var released: Object?

        for _ in 0 ..< 10 {
            let transientScene = Object(context: context, label: "transient")
            transientScene.attach(shared)
            released = transientScene
        }

        XCTAssertNil(released, "an attachment does not keep its container alive")
        let lastScene = Object(context: context, label: "last")
        lastScene.attach(shared)
        assertChangeAdvancesRoot(lastScene) { shared.add(Object(context: context, label: "below")) }
    }

    // MARK: - Ownership

    func testAnIndexDoesNotKeepItsRootAlive() throws {
        let context = try makeContext()
        weak var weakObjectRoot: Object?
        weak var weakMeshRoot: Object?
        weak var weakLightRoot: Object?

        do {
            let objectRoot = Object(context: context, label: "object root")
            let meshRoot = makeMesh(context, "mesh root")
            let lightRoot = DirectionalLight(context: context, color: .one)
            for root in [objectRoot, meshRoot, lightRoot] as [Object] {
                root.add(Object(context: context, label: "child"))
                _ = root.sceneIndex
            }
            weakObjectRoot = objectRoot
            weakMeshRoot = meshRoot
            weakLightRoot = lightRoot
        }

        XCTAssertNil(weakObjectRoot)
        XCTAssertNil(weakMeshRoot)
        XCTAssertNil(weakLightRoot)
    }

    func testARemovedSubtreeIsReleasedRightAway() throws {
        let context = try makeContext()
        let root = Object(context: context, label: "root")
        weak var weakSubtree: Object?

        do {
            let subtree = Object(context: context, label: "subtree")
            subtree.add(Object(context: context, label: "leaf"))
            root.add(subtree)
            _ = root.sceneIndex
            root.remove(subtree)
            weakSubtree = subtree
        }

        XCTAssertNil(weakSubtree)
    }

    func testAnIndexOutlivingItsRootKeepsOnlyItsDescendants() throws {
        let context = try makeContext()
        weak var weakRoot: Object?
        let index: SceneIndex

        do {
            let root = Object(context: context, label: "root")
            root.add(Object(context: context, label: "child"))
            index = root.sceneIndex
            weakRoot = root
        }

        XCTAssertNil(weakRoot)
        XCTAssertEqual(labels(index), ["child"], "still readable, holding its descendants")
    }
}
