//
//  SceneIndex.swift
//  Satin
//

import Foundation

/// One root's descendants, flattened in depth-first preorder and cast once, so a frame can walk the
/// scene without re-gathering or re-casting it. `Object.sceneIndex` builds it when the root's
/// structure has changed and returns the cached one otherwise.
///
/// An index is an immutable snapshot of the structure it was built from: a later change builds a new
/// index and never alters this one. It holds the descendants strongly and never refers to its root,
/// so a root never retains itself through its index. An index kept after its root goes away keeps its
/// descendants alive until it is released.
///
/// An object reachable through several containers appears once per occurrence. A child that would
/// re-enter an object already on its path, a cycle through `attach`, is skipped and counted in
/// `skippedCycles`.
public final class SceneIndex {
    public struct Entry {
        public let object: Object
        public let renderable: Renderable?
        public let light: Light?
        public let environment: IBLEnvironment?

        /// The index one past this entry's last descendant: where the walk continues when it skips
        /// this entry's subtree.
        public fileprivate(set) var subtreeEnd: Int

        /// The index of the entry that contains this one, or -1 for a direct child of the root.
        public let parentEntry: Int
    }

    /// The root's descendants in depth-first preorder, the order today's traversal visits them.
    public let entries: [Entry]

    public let renderables: [Renderable]
    public let lights: [Light]
    public let environments: [IBLEnvironment]
    public let cameras: [Camera]

    /// Branches left out because they would re-enter an object already on their path.
    public let skippedCycles: Int

    /// The root's structure revision this index was built from.
    let revision: UInt64

    init(root: Object) {
        var entries: [Entry] = []
        var path: Set<ObjectIdentifier> = [ObjectIdentifier(root)]
        var skippedCycles = 0

        func appendDescendants(of object: Object, parentEntry: Int) {
            for child in object.children {
                let childIdentifier = ObjectIdentifier(child)
                guard !path.contains(childIdentifier) else {
                    skippedCycles += 1
                    continue
                }

                let entryIndex = entries.count
                entries.append(
                    Entry(
                        object: child,
                        renderable: child as? Renderable,
                        light: child as? Light,
                        environment: child as? IBLEnvironment,
                        subtreeEnd: entryIndex + 1,
                        parentEntry: parentEntry
                    )
                )

                path.insert(childIdentifier)
                appendDescendants(of: child, parentEntry: entryIndex)
                path.remove(childIdentifier)

                entries[entryIndex].subtreeEnd = entries.count
            }
        }

        appendDescendants(of: root, parentEntry: -1)

#if DEBUG
        if skippedCycles > 0 {
            print("SceneIndex: skipped \(skippedCycles) cyclic branch(es) under \(root.label)")
        }
#endif

        self.entries = entries
        self.renderables = entries.compactMap(\.renderable)
        self.lights = entries.compactMap(\.light)
        self.environments = entries.compactMap(\.environment)
        self.cameras = entries.compactMap { $0.object as? Camera }
        self.skippedCycles = skippedCycles
        self.revision = root.structureRevision
    }
}
