@testable import Satin
import Metal
import XCTest

/// `SceneTraversal` must update and collect exactly as Satin's recursive traversal always has, in
/// every case, including structure and visibility changes made inside `update()`. Each scenario is
/// built twice from scratch, once run through that recursion (kept here as the reference) and once
/// through `SceneTraversal`, and the update order and every collected list must match.
final class SceneTraversalTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    // MARK: - Outcome

    /// Everything a pass produces, by label.
    private struct Outcome: Equatable {
        var updates: [String] = []
        var objects: [String] = []
        var layers: [Int: [String]] = [:]
        var sortedLayers: [Int: [String]] = [:]
        var lights: [String] = []
        var lightReceivers: [String] = []
        var shadowCasters: [String] = []
        var shadowReceivers: [String] = []
    }

    /// The recursive traversal `RenderEncoder` used before `SceneTraversal`, unchanged.
    private func referenceUpdateAndCollect(_ object: Object, visible: Bool, into outcome: inout Outcome, renderables: inout [Int: [Renderable]]) {
        object.update()

        if object.visible, visible {
            outcome.objects.append(object.label)

            if object is Light {
                outcome.lights.append(object.label)
            }

            if let renderable = object as? Renderable {
                renderables[renderable.renderLayer.rawValue, default: []].append(renderable)
                if renderable.lighting { outcome.lightReceivers.append(object.label) }
                if renderable.receiveShadow { outcome.shadowReceivers.append(object.label) }
                if renderable.castShadow { outcome.shadowCasters.append(object.label) }
            }

            for child in object.children {
                referenceUpdateAndCollect(child, visible: object.visible && visible, into: &outcome, renderables: &renderables)
            }
        }
    }

    /// Builds a fresh scene, logging every `update()` into `log`.
    private typealias Scenario = (_ context: Context, _ log: Log) -> Object

    private final class Log {
        var updates: [String] = []
        /// Keeps a scenario's objects alive for the run, so a change script may refer to an object
        /// another script removes.
        var retained: [Object] = []
    }

    private func referenceOutcome(_ scenario: Scenario) -> Outcome {
        let log = Log()
        let scene = scenario(context, log)
        var outcome = Outcome()
        var renderables: [Int: [Renderable]] = [:]
        referenceUpdateAndCollect(scene, visible: true, into: &outcome, renderables: &renderables)
        outcome.updates = log.updates
        for (layer, layerRenderables) in renderables {
            outcome.layers[layer] = layerRenderables.map(\.label)
            outcome.sortedLayers[layer] = layerRenderables.sorted { $0.renderOrder < $1.renderOrder }.map(\.label)
        }
        return outcome
    }

    private func traversalOutcome(_ scenario: Scenario, passes: Int = 1) -> Outcome {
        let log = Log()
        let scene = scenario(context, log)
        let traversal = SceneTraversal()
        let collection = RenderCollection()
        for _ in 0 ..< passes {
            log.updates.removeAll()
            collection.reset()
            traversal.updateAndCollect(scene: scene, into: collection)
        }
        return outcome(of: collection, updates: log.updates)
    }

    private func outcome(of collection: RenderCollection, updates: [String]) -> Outcome {
        var outcome = Outcome()
        outcome.updates = updates
        outcome.objects = collection.objects.map(\.object.label)
        for layer in collection.activeLayers {
            outcome.layers[layer] = collection.renderables(renderLayer: layer, sorted: false).map(\.label)
            outcome.sortedLayers[layer] = collection.renderables(renderLayer: layer, sorted: true).map(\.label)
        }
        outcome.lights = collection.lights.map(\.label)
        outcome.lightReceivers = collection.lightReceivers.map(\.label)
        outcome.shadowCasters = collection.shadowCasters.map(\.label)
        outcome.shadowReceivers = collection.shadowReceivers.map(\.label)
        return outcome
    }

    private func assertMatchesReference(_ scenario: Scenario, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(traversalOutcome(scenario), referenceOutcome(scenario), file: file, line: line)
    }

    // MARK: - Building

    private func object(_ label: String, _ log: Log, visible: Bool = true, onUpdate: (() -> Void)? = nil) -> Object {
        let object = Object(context: context, label: label, visible: visible)
        logging(object, log, onUpdate: onUpdate)
        return object
    }

    private func mesh(_ label: String, _ log: Log, renderOrder: Int = 0, layer: RenderLayer = .opaque, castShadow: Bool = false, receiveShadow: Bool = false, onUpdate: (() -> Void)? = nil) -> Mesh {
        let mesh = Mesh(context: context, label: label, geometry: Geometry(context: context), material: BasicColorMaterial(context: context), renderOrder: renderOrder, renderLayer: layer)
        mesh.castShadow = castShadow
        mesh.receiveShadow = receiveShadow
        logging(mesh, log, onUpdate: onUpdate)
        return mesh
    }

    private func light(_ label: String, _ log: Log) -> DirectionalLight {
        let light = DirectionalLight(context: context, label: label, color: .one)
        logging(light, log, onUpdate: nil)
        return light
    }

    private func logging(_ object: Object, _ log: Log, onUpdate: (() -> Void)?) {
        object.onUpdate = { [unowned object, unowned log] in
            log.updates.append(object.label)
            onUpdate?()
        }
    }

    // MARK: - Static Scenes

    func testStaticScenesMatch() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let a = self.mesh("a", log, renderOrder: 2, castShadow: true)
            let hidden = self.object("hidden", log, visible: false)
            let underHidden = self.mesh("under hidden", log)
            let b = self.mesh("b", log, renderOrder: 1, layer: .transparent, receiveShadow: true)
            let c = self.mesh("c", log, renderOrder: 0)
            let light = self.light("light", log)
            root.add(a)
            a.add(hidden)
            hidden.add(underHidden)
            a.add(light)
            root.add(b)
            b.add(c)
            return root
        }
    }

    func testARenderableRootMatches() {
        assertMatchesReference { context, log in
            let root = self.mesh("root", log)
            root.add(self.mesh("child", log))
            return root
        }
    }

    func testAHiddenRootMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log, visible: false)
            root.add(self.mesh("child", log))
            return root
        }
    }

    func testSharedChildrenMatch() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let first = self.object("first", log)
            let second = self.object("second", log)
            let shared = self.mesh("shared", log)
            root.add(first)
            root.add(second)
            first.add(shared)
            second.attach(shared)
            return root
        }
    }

    // MARK: - Visibility Changes During update()

    func testHidingALaterNodeMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let later = self.mesh("later", log)
            later.add(self.mesh("under later", log))
            let first = self.mesh("first", log, onUpdate: { [unowned later] in later.visible = false })
            root.add(first)
            root.add(later)
            return root
        }
    }

    func testAnEarlierSiblingHidingTheSharedParentMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let parent = self.object("parent", log)
            let laterSibling = self.mesh("later sibling", log)
            laterSibling.add(self.mesh("under later sibling", log))
            let first = self.mesh("first", log, onUpdate: { [unowned parent] in parent.visible = false })
            root.add(parent)
            parent.add(first)
            parent.add(laterSibling)
            root.add(self.mesh("after parent", log))
            return root
        }
    }

    func testHidingItsOwnParentMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let parent = self.object("parent", log)
            let child = self.mesh("child", log)
            child.onUpdate = { [unowned child, unowned parent, unowned log] in
                log.updates.append(child.label)
                parent.visible = false
            }
            root.add(parent)
            parent.add(child)
            parent.add(self.mesh("child sibling", log))
            return root
        }
    }

    func testUnhidingALaterNodeMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let later = self.object("later", log, visible: false)
            later.add(self.mesh("under later", log))
            root.add(self.mesh("first", log, onUpdate: { [unowned later] in later.visible = true }))
            root.add(later)
            return root
        }
    }

    // MARK: - Structure Changes During update()

    func testAddingItsOwnChildMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let a = self.object("a", log)
            a.onUpdate = { [unowned a, unowned log] in
                log.updates.append(a.label)
                a.add(self.mesh("added under a", log))
            }
            root.add(a)
            root.add(self.mesh("b", log))
            return root
        }
    }

    func testRemovingAndReorderingItsOwnChildrenMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let a = self.object("a", log)
            let first = self.mesh("first", log)
            let second = self.mesh("second", log)
            let third = self.mesh("third", log)
            a.add(first)
            a.add(second)
            a.add(third)
            log.retained = [first, second, third]
            a.onUpdate = { [unowned a, unowned first, unowned log] in
                log.updates.append(a.label)
                a.remove(first)
                a.children = a.children.reversed()
            }
            root.add(a)
            return root
        }
    }

    func testAddingUnderAFinishedNodeMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let finished = self.object("finished", log)
            let later = self.object("later", log)
            later.onUpdate = { [unowned later, unowned finished, unowned log] in
                log.updates.append(later.label)
                finished.add(self.mesh("added under finished", log))
            }
            root.add(finished)
            root.add(later)
            root.add(self.mesh("last", log))
            return root
        }
    }

    func testRemovingALaterSiblingMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let later = self.mesh("later", log)
            let first = self.object("first", log)
            first.onUpdate = { [unowned first, unowned root, unowned later, unowned log] in
                log.updates.append(first.label)
                root.remove(later)
            }
            root.add(first)
            root.add(later)
            return root
        }
    }

    func testRemovingItselfMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let parent = self.object("parent", log)
            let leaving = self.mesh("leaving", log)
            leaving.add(self.mesh("under leaving", log))
            leaving.onUpdate = { [unowned leaving, unowned log] in
                log.updates.append(leaving.label)
                leaving.removeFromParent()
            }
            root.add(parent)
            parent.add(leaving)
            parent.add(self.mesh("after leaving", log))
            root.add(self.mesh("after parent", log))
            return root
        }
    }

    func testReparentingMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let finished = self.mesh("finished", log)
            let unfinished = self.mesh("unfinished", log)
            let mover = self.object("mover", log)
            mover.onUpdate = { [unowned mover, unowned finished, unowned unfinished, unowned log] in
                log.updates.append(mover.label)
                mover.add(finished)
                mover.add(unfinished)
            }
            root.add(finished)
            root.add(mover)
            root.add(unfinished)
            return root
        }
    }

    func testSeveralChangesInOnePassMatch() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            for index in 0 ..< 4 {
                let node = self.object("node \(index)", log)
                node.onUpdate = { [unowned node, unowned log] in
                    log.updates.append(node.label)
                    node.add(self.mesh("added under node \(index)", log))
                }
                root.add(node)
            }
            return root
        }
    }

    func testAChangeInTheRootsOwnUpdateMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            root.onUpdate = { [unowned root, unowned log] in
                log.updates.append(root.label)
                root.add(self.mesh("added under root", log))
            }
            root.add(self.mesh("existing", log))
            return root
        }
    }

    func testAChangeAtTheLastEntryMatches() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            root.add(self.mesh("first", log))
            let last = self.object("last", log)
            last.onUpdate = { [unowned last, unowned log] in
                log.updates.append(last.label)
                last.add(self.mesh("added under last", log))
            }
            root.add(last)
            return root
        }
    }

    // MARK: - The Switch to Recursion

    func testTheNodeThatChangesStructureIsUpdatedAndCollectedOnce() {
        for changesInRoot in [true, false] {
            let log = Log()
            let root = object("root", log)
            let deep = object("deep", log)
            let changer: Object = changesInRoot ? root : deep
            changer.onUpdate = { [unowned changer, unowned log] in
                log.updates.append(changer.label)
                changer.add(self.mesh("added", log))
            }
            let middle = object("middle", log)
            root.add(middle)
            middle.add(deep)

            let collection = RenderCollection()
            SceneTraversal().updateAndCollect(scene: root, into: collection)

            XCTAssertEqual(log.updates.filter { $0 == changer.label }.count, 1)
            XCTAssertEqual(collection.objects.filter { $0.object === changer }.count, 1)
        }
    }

    func testASharedObjectThatChangesStructureIsStillVisitedLater() {
        assertMatchesReference { context, log in
            let root = self.object("root", log)
            let first = self.object("first", log)
            let second = self.object("second", log)
            let shared = self.object("shared", log)
            var addedOnce = false
            shared.onUpdate = { [unowned shared, unowned log] in
                log.updates.append(shared.label)
                if !addedOnce {
                    addedOnce = true
                    shared.add(self.mesh("added under shared", log))
                }
            }
            root.add(first)
            root.add(second)
            first.add(shared)
            second.attach(shared)
            return root
        }
    }

    func testABackEdgeAddedDuringTheSwitchEndsThePass() {
        let log = Log()
        let root = object("root", log)
        let ancestor = object("ancestor", log)
        let node = object("node", log)
        node.onUpdate = { [unowned node, unowned ancestor, unowned log] in
            log.updates.append(node.label)
            node.attach(ancestor)
        }
        root.add(ancestor)
        ancestor.add(node)

        let collection = RenderCollection()
        SceneTraversal().updateAndCollect(scene: root, into: collection)

        XCTAssertEqual(log.updates, ["root", "ancestor", "node"])
        XCTAssertEqual(collection.objects.map(\.object.label), ["root", "ancestor", "node"])
    }

    // MARK: - Repeated Passes

    func testLaterPassesUseTheRebuiltIndex() {
        let scenario: Scenario = { context, log in
            let root = self.object("root", log)
            let grower = self.object("grower", log)
            grower.onUpdate = { [unowned grower, unowned log] in
                log.updates.append(grower.label)
                if grower.children.count < 2 {
                    grower.add(self.mesh("grown \(grower.children.count)", log))
                }
            }
            root.add(grower)
            return root
        }

        // The third pass sees two grown children and changes nothing.
        let outcome = traversalOutcome(scenario, passes: 3)
        XCTAssertEqual(outcome.updates, ["root", "grower", "grown 0", "grown 1"])
        XCTAssertEqual(outcome.objects, ["root", "grower", "grown 0", "grown 1"])
    }

    // MARK: - Randomised

    func testRandomScenesAndChangesMatch() {
        for seed in 1 ... 40 {
            let scenario = randomScenario(seed: UInt64(seed))
            XCTAssertEqual(traversalOutcome(scenario), referenceOutcome(scenario), "seed \(seed)")
        }
    }

    /// A deterministic scene and change script for `seed`: both runs build exactly the same thing.
    private func randomScenario(seed: UInt64) -> Scenario {
        { context, log in
            var generator = SeededGenerator(state: seed)
            var nodes: [Object] = []
            let root = self.object("root", log)
            nodes.append(root)

            for index in 0 ..< 24 {
                let parent = nodes[Int.random(in: 0 ..< nodes.count, using: &generator)]
                let isMesh = Bool.random(using: &generator)
                let node: Object = isMesh
                    ? self.mesh("n\(index)", log, renderOrder: Int.random(in: 0 ..< 3, using: &generator), layer: RenderLayer(rawValue: Int.random(in: 0 ..< 3, using: &generator)), castShadow: Bool.random(using: &generator), receiveShadow: Bool.random(using: &generator))
                    : self.object("n\(index)", log, visible: Int.random(in: 0 ..< 5, using: &generator) > 0)
                parent.add(node)
                nodes.append(node)
            }

            log.retained = nodes
            var addedCount = 0
            for node in nodes.dropFirst() where Int.random(in: 0 ..< 4, using: &generator) == 0 {
                let action = Int.random(in: 0 ..< 4, using: &generator)
                let target = nodes[Int.random(in: 0 ..< nodes.count, using: &generator)]
                let visibleTarget = nodes[Int.random(in: 0 ..< nodes.count, using: &generator)]
                node.onUpdate = { [unowned node, unowned target, unowned visibleTarget, unowned log] in
                    log.updates.append(node.label)
                    switch action {
                    case 0:
                        addedCount += 1
                        node.add(self.mesh("added \(addedCount)", log))
                    case 1:
                        node.children.first?.removeFromParent()
                    case 2:
                        visibleTarget.visible.toggle()
                    default:
                        if target !== node, !target.isAncestor(of: node) {
                            node.add(target)
                        }
                    }
                }
            }
            return root
        }
    }

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }
}

private extension Object {
    func isAncestor(of object: Object) -> Bool {
        var current = object.parent
        while let ancestor = current {
            if ancestor === self { return true }
            current = ancestor.parent
        }
        return false
    }
}
