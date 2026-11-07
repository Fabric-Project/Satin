//
//  RenderCollection.swift
//  Satin
//

import Foundation

/// What one update pass collected from a scene: the visible objects in visit order, the renderables
/// of each render layer, the lights, and the renderables that receive light or cast and receive
/// shadows. `RenderEncoder` resets it at the start of every pass and fills it through
/// `SceneTraversal`; its storage persists across passes.
final class RenderCollection {
    struct CollectedObject {
        let object: Object
        let renderable: Renderable?
        let environment: IBLEnvironment?
    }

    /// Everything a pass collects, in one stored struct: a collect is one exclusivity check, not one
    /// per array it appends to.
    private struct Storage {
        // Contiguous: never bridged, so reads skip the NSArray checks.
        var objects = ContiguousArray<CollectedObject>()
        var lights = ContiguousArray<Light>()
        var lightReceivers = ContiguousArray<Renderable>()
        var shadowCasters = ContiguousArray<Renderable>()
        var shadowReceivers = ContiguousArray<Renderable>()

        /// The render layers holding at least one renderable this pass, ascending. A layer emptied
        /// since an earlier pass is not in it.
        var activeLayers: [Int] = []

        /// One list per render layer ever collected, kept across passes and found by a short scan: a
        /// scene uses a handful of layers.
        var layerRenderLists: [(renderLayer: Int, renderList: RenderList)] = []

        func renderList(renderLayer: Int) -> RenderList? {
            for entry in layerRenderLists where entry.renderLayer == renderLayer {
                return entry.renderList
            }
            return nil
        }

        mutating func reset() {
            objects.removeAll(keepingCapacity: true)
            lights.removeAll(keepingCapacity: true)
            lightReceivers.removeAll(keepingCapacity: true)
            shadowCasters.removeAll(keepingCapacity: true)
            shadowReceivers.removeAll(keepingCapacity: true)
            activeLayers.removeAll(keepingCapacity: true)
            for entry in layerRenderLists {
                entry.renderList.removeAll(keepingCapacity: true)
            }
        }

        /// Takes the renderable's layer and flags already read: they can be overridden, and an
        /// override must not run while this storage is being written.
        mutating func collect(object: Object, renderable: Renderable?, renderLayer: Int,
                              lighting: Bool, receiveShadow: Bool, castShadow: Bool,
                              light: Light?, environment: IBLEnvironment?) {
            objects.append(CollectedObject(object: object, renderable: renderable, environment: environment))

            if let light {
                lights.append(light)
            }

            guard let renderable else { return }

            let renderList: RenderList
            if let existingRenderList = self.renderList(renderLayer: renderLayer) {
                renderList = existingRenderList
            } else {
                renderList = RenderList()
                layerRenderLists.append((renderLayer: renderLayer, renderList: renderList))
            }

            if renderList.isEmpty {
                let insertionIndex = activeLayers.firstIndex { $0 > renderLayer } ?? activeLayers.count
                activeLayers.insert(renderLayer, at: insertionIndex)
            }
            renderList.append(renderable)

            if lighting {
                lightReceivers.append(renderable)
            }

            if receiveShadow {
                shadowReceivers.append(renderable)
            }

            if castShadow {
                shadowCasters.append(renderable)
            }
        }
    }

    private var storage = Storage()

    var objects: ContiguousArray<CollectedObject> { storage.objects }
    var lights: ContiguousArray<Light> { storage.lights }
    var lightReceivers: ContiguousArray<Renderable> { storage.lightReceivers }
    var shadowCasters: ContiguousArray<Renderable> { storage.shadowCasters }
    var shadowReceivers: ContiguousArray<Renderable> { storage.shadowReceivers }

    /// The render layers holding at least one renderable this pass, ascending. A layer emptied since
    /// an earlier pass is not in it.
    var activeLayers: [Int] { storage.activeLayers }

    /// Whether this pass collected no renderables.
    var isEmpty: Bool {
        storage.activeLayers.isEmpty
    }

    func reset() {
        storage.reset()
    }

    func includeLights(_ occurrences: [RecordedLightOccurrence]) {
        storage.lights.append(contentsOf: occurrences)
    }

    /// Collects one visible object. Its render layer and lighting and shadow flags are read now.
    /// Everything overridable is read or set here, before `storage` is written.
    func collect(object: Object, renderable: Renderable?, light: Light?, environment: IBLEnvironment?) {
        if let light {
            light.shadowIndex = -1
            light.projectorIndex = -1
        }
        storage.collect(object: object, renderable: renderable,
                        renderLayer: renderable?.renderLayer.rawValue ?? 0,
                        lighting: renderable?.lighting ?? false,
                        receiveShadow: renderable?.receiveShadow ?? false,
                        castShadow: renderable?.castShadow ?? false,
                        light: light, environment: environment)
    }

    /// The renderables of `renderLayer` this pass, sorted by render order or in collection order. A
    /// layer with none, such as one holding only scheduled commands, gives an empty list.
    func renderables(renderLayer: Int, sorted: Bool) -> ContiguousArray<Renderable> {
        storage.renderList(renderLayer: renderLayer)?.getRenderables(sorted: sorted) ?? []
    }
}
