//
//  RenderList.swift
//
//
//  Created by Reza Ali on 12/12/23.
//

import Foundation

/// The renderables of one render layer for one update pass. It persists across passes: emptying it
/// keeps its storage. The sorted order is made on the first sorted read of a pass and reused for the
/// rest of it; unsorted reads keep the order renderables were appended in.
final class RenderList {
    public var isEmpty: Bool {
        renderables.isEmpty
    }

    // Contiguous: never bridged, so reads skip the NSArray checks.
    private var renderables = ContiguousArray<Renderable>()
    private var sortedRenderables = ContiguousArray<Renderable>()
    private var sortedRenderablesAreCurrent = false

    public func append(_ renderable: Renderable) {
        renderables.append(renderable)
        sortedRenderablesAreCurrent = false
    }

    public func removeAll(keepingCapacity: Bool = true) {
        renderables.removeAll(keepingCapacity: keepingCapacity)
        sortedRenderables.removeAll(keepingCapacity: keepingCapacity)
        sortedRenderablesAreCurrent = false
    }

    public func getRenderables(sorted: Bool) -> ContiguousArray<Renderable> {
        guard sorted else { return renderables }

        if !sortedRenderablesAreCurrent {
            sortedRenderables.removeAll(keepingCapacity: true)
            sortedRenderables.append(contentsOf: renderables)
            sortedRenderables.sort { $0.renderOrder < $1.renderOrder }
            sortedRenderablesAreCurrent = true
        }
        return sortedRenderables
    }
}
