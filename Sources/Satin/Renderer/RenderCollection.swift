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

    // Contiguous: never bridged, so reads skip the NSArray checks.
    private(set) var objects = ContiguousArray<CollectedObject>()
    private(set) var lights = ContiguousArray<Light>()
    private(set) var lightReceivers = ContiguousArray<Renderable>()
    private(set) var shadowCasters = ContiguousArray<Renderable>()
    private(set) var shadowReceivers = ContiguousArray<Renderable>()

    /// The render layers holding at least one renderable this pass, ascending. A layer emptied since
    /// an earlier pass is not in it.
    private(set) var activeLayers: [Int] = []

    /// One list per render layer ever collected, kept across passes and found by a short scan: a
    /// scene uses a handful of layers.
    private var layerRenderLists: [(renderLayer: Int, renderList: RenderList)] = []

    private func renderList(renderLayer: Int) -> RenderList? {
        for entry in layerRenderLists where entry.renderLayer == renderLayer {
            return entry.renderList
        }
        return nil
    }

    /// Whether this pass collected no renderables.
    var isEmpty: Bool {
        activeLayers.isEmpty
    }

    func reset() {
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

    /// Collects one visible object. Its render layer and lighting and shadow flags are read now.
    func collect(object: Object, renderable: Renderable?, light: Light?, environment: IBLEnvironment?) {
        objects.append(CollectedObject(object: object, renderable: renderable, environment: environment))

        if let light {
            light.shadowIndex = -1
            light.projectorIndex = -1
            lights.append(light)
        }

        guard let renderable else { return }

        let renderLayer = renderable.renderLayer.rawValue
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

        if renderable.lighting {
            lightReceivers.append(renderable)
        }

        if renderable.receiveShadow {
            shadowReceivers.append(renderable)
        }

        if renderable.castShadow {
            shadowCasters.append(renderable)
        }
    }

    /// The renderables of `renderLayer` this pass, sorted by render order or in collection order. A
    /// layer with none, such as one holding only scheduled commands, gives an empty list.
    func renderables(renderLayer: Int, sorted: Bool) -> ContiguousArray<Renderable> {
        renderList(renderLayer: renderLayer)?.getRenderables(sorted: sorted) ?? []
    }
}
