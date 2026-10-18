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

    private(set) var objects: [CollectedObject] = []
    private(set) var lights: [Light] = []
    private(set) var lightReceivers: [Renderable] = []
    private(set) var shadowCasters: [Renderable] = []
    private(set) var shadowReceivers: [Renderable] = []

    /// The render layers holding at least one renderable this pass, ascending. A layer emptied since
    /// an earlier pass is not in it.
    private(set) var activeLayers: [Int] = []

    private var renderLists: [Int: RenderList] = [:]

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
        for renderList in renderLists.values {
            renderList.removeAll(keepingCapacity: true)
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
        if let existingRenderList = renderLists[renderLayer] {
            renderList = existingRenderList
        } else {
            renderList = RenderList()
            renderLists[renderLayer] = renderList
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
    func renderables(renderLayer: Int, sorted: Bool) -> [Renderable] {
        renderLists[renderLayer]?.getRenderables(sorted: sorted) ?? []
    }
}
