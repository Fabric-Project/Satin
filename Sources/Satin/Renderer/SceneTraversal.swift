//
//  SceneTraversal.swift
//  Satin
//

import Foundation

/// Updates a scene and collects what is visible, once per update pass.
///
/// The result is exactly that of the recursive traversal Satin has always used: each object is
/// updated, then, if it and the visibility it was reached with are visible, it is collected and its
/// children are visited, each reached with its parent's visibility read again at that moment. A
/// hidden object is updated but nothing below it is visited.
///
/// While the scene's structure stays as it was when the pass began, the walk runs over the scene's
/// cached `SceneIndex`, with no recursion and no casting. If an `update()` changes the structure,
/// the walk carries on from that point as the recursive traversal itself, resumed with the same
/// state that traversal would have, so every change during the pass is handled as it always was.
final class SceneTraversal {
    /// Collect an already-updated scene without running its hooks a second time.
    func collect(scene: Object, into collection: RenderCollection) {
        guard scene.visible else { return }
        collection.collect(object: scene, renderable: scene as? Renderable,
                           light: scene as? Light, environment: scene as? IBLEnvironment)
        let entries = scene.sceneIndex.entries
        var index = 0
        while index < entries.count {
            let entry = entries[index]
            guard entry.object.visible else { index = entry.subtreeEnd; continue }
            collection.collect(object: entry.object, renderable: entry.renderable,
                               light: entry.light, environment: entry.environment)
            index += 1
        }
    }
    /// The visibility each index entry was reached with, by entry. Reused across passes.
    private var entryCallVisible: [Bool] = []

    /// The objects on the recursive traversal's current path, so a cycle is skipped instead of
    /// recursing forever.
    private var recursionPath: Set<ObjectIdentifier> = []

    func updateAndCollect(scene: Object, into collection: RenderCollection) {
        let revision = scene.structureRevision

        scene.update()

        guard scene.structureRevision == revision else {
            recursionPath.removeAll(keepingCapacity: true)
            finishUpdatedNode(scene, visible: true, into: collection)
            return
        }

        guard scene.visible else { return }

        collection.collect(
            object: scene,
            renderable: scene as? Renderable,
            light: scene as? Light,
            environment: scene as? IBLEnvironment
        )

        let entries = scene.sceneIndex.entries
        if entryCallVisible.count < entries.count {
            entryCallVisible.append(contentsOf: repeatElement(false, count: entries.count - entryCallVisible.count))
        }

        var entryIndex = 0
        while entryIndex < entries.count {
            let entry = entries[entryIndex]

            let callVisible = entry.parentEntry < 0
                ? scene.visible
                : entries[entry.parentEntry].object.visible && entryCallVisible[entry.parentEntry]
            entryCallVisible[entryIndex] = callVisible

            entry.object.update()

            guard scene.structureRevision == revision else {
                continueRecursively(after: entryIndex, of: entries, scene: scene, into: collection)
                return
            }

            if entry.object.visible, callVisible {
                collection.collect(
                    object: entry.object,
                    renderable: entry.renderable,
                    light: entry.light,
                    environment: entry.environment
                )
                entryIndex += 1
            } else {
                entryIndex = entry.subtreeEnd
            }
        }
    }

    // MARK: - Recursive Traversal

    /// Updates `object`, then finishes it.
    private func recursiveUpdateAndCollect(_ object: Object, visible: Bool, into collection: RenderCollection) {
        guard !recursionPath.contains(ObjectIdentifier(object)) else { return }

        object.update()
        finishUpdatedNode(object, visible: visible, into: collection)
    }

    /// Everything after an object's `update()`: collects it if visible and visits its current children.
    private func finishUpdatedNode(_ object: Object, visible: Bool, into collection: RenderCollection) {
        guard object.visible, visible else { return }

        collection.collect(
            object: object,
            renderable: object as? Renderable,
            light: object as? Light,
            environment: object as? IBLEnvironment
        )

        let objectIdentifier = ObjectIdentifier(object)
        recursionPath.insert(objectIdentifier)
        for child in object.children {
            recursiveUpdateAndCollect(child, visible: object.visible && visible, into: collection)
        }
        recursionPath.remove(objectIdentifier)
    }

    /// Carries on as the recursive traversal after `entries[currentEntry]`'s `update()` changed the
    /// scene's structure. The recursion would be part way through each ancestor's children, copied
    /// before anything changed, so those copies are the ones recorded in the index.
    private func continueRecursively(
        after currentEntry: Int,
        of entries: [SceneIndex.Entry],
        scene: Object,
        into collection: RenderCollection
    ) {
        let currentObject = entries[currentEntry].object

        // The path the recursion would be on: the root, the current entry's ancestors and the entry.
        recursionPath.removeAll(keepingCapacity: true)
        recursionPath.insert(ObjectIdentifier(scene))
        var ancestorEntry = entries[currentEntry].parentEntry
        while ancestorEntry >= 0 {
            recursionPath.insert(ObjectIdentifier(entries[ancestorEntry].object))
            ancestorEntry = entries[ancestorEntry].parentEntry
        }
        recursionPath.insert(ObjectIdentifier(currentObject))

        finishUpdatedNode(currentObject, visible: entryCallVisible[currentEntry], into: collection)
        recursionPath.remove(ObjectIdentifier(currentObject))

        // Resume each enclosing loop over its recorded children, from the deepest ancestor to the root.
        var childEntry = currentEntry
        var containerEntry = entries[currentEntry].parentEntry
        while true {
            let containerObject = containerEntry < 0 ? scene : entries[containerEntry].object
            let containerCallVisible = containerEntry < 0 ? true : entryCallVisible[containerEntry]
            let containerEnd = containerEntry < 0 ? entries.count : entries[containerEntry].subtreeEnd

            var siblingEntry = entries[childEntry].subtreeEnd
            while siblingEntry < containerEnd {
                recursiveUpdateAndCollect(
                    entries[siblingEntry].object,
                    visible: containerObject.visible && containerCallVisible,
                    into: collection
                )
                siblingEntry = entries[siblingEntry].subtreeEnd
            }

            recursionPath.remove(ObjectIdentifier(containerObject))

            guard containerEntry >= 0 else { return }
            childEntry = containerEntry
            containerEntry = entries[containerEntry].parentEntry
        }
    }
}
