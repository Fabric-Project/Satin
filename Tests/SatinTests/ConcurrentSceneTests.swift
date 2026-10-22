@testable import Satin
import Metal
import simd
import XCTest

/// Separate scenes may be owned by separate threads: two renderers on their own queues, each
/// updating and reading only its own objects. Nothing process-wide may make that a data race.
/// Run under Thread Sanitizer for this to mean anything; without it the results still have to hold.
final class ConcurrentSceneTests: XCTestCase {
    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    /// Moves `root` and rebuilds the tree's structure each step, checking the leaf's world position.
    private func exercise(root: Object, middle: Object, leaf: Object, steps: Int) -> Bool {
        var allCorrect = true
        for step in 0 ..< steps {
            let offset = Float(step % 17)
            root.position = [offset, 0, 0]
            middle.orientation = simd_quatf(angle: Float(step) * 0.01, axis: [0, 1, 0])
            if step % 5 == 0 {
                middle.remove(leaf)
                middle.add(leaf)
            }
            let world = leaf.worldPosition
            allCorrect = allCorrect && abs(world.x - offset) < 1e-4
            _ = root.sceneIndex
        }
        return allCorrect
    }

    func testSeparateScenesUpdateConcurrentlyOnTheirOwnQueues() throws {
        let context = try makeContext()
        let scenes = (0 ..< 2).map { index -> (root: Object, middle: Object, leaf: Object) in
            let leaf = Object(context: context, label: "Leaf \(index)")
            let middle = Object(context: context, label: "Middle \(index)", [leaf])
            let root = Object(context: context, label: "Root \(index)", [middle])
            return (root, middle, leaf)
        }
        let queues = (0 ..< 2).map { DispatchQueue(label: "Scene \($0)") }
        let lock = UnfairLock()
        var results: [Bool] = []
        let group = DispatchGroup()
        for index in 0 ..< 2 {
            let scene = scenes[index]
            queues[index].async(group: group) {
                let correct = self.exercise(root: scene.root, middle: scene.middle, leaf: scene.leaf, steps: 2000)
                lock.sync { results.append(correct) }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        lock.sync { XCTAssertEqual(results, [true, true]) }
    }
}
