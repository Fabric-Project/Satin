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
    /// One stored struct, so an append is one exclusivity check, not two.
    private struct State {
        // Contiguous: never bridged, so reads skip the NSArray checks.
        var renderables = ContiguousArray<Renderable>()
        var sortedRenderables = ContiguousArray<Renderable>()
        var sortedRenderablesAreCurrent = false

        mutating func append(_ renderable: Renderable) {
            renderables.append(renderable)
            sortedRenderablesAreCurrent = false
        }

        mutating func removeAll(keepingCapacity: Bool) {
            renderables.removeAll(keepingCapacity: keepingCapacity)
            sortedRenderables.removeAll(keepingCapacity: keepingCapacity)
            sortedRenderablesAreCurrent = false
        }

        mutating func sorted() -> ContiguousArray<Renderable> {
            if !sortedRenderablesAreCurrent {
                sortedRenderables.removeAll(keepingCapacity: true)
                sortedRenderables.append(contentsOf: renderables)
                sortedRenderables.sort { $0.renderOrder < $1.renderOrder }
                sortedRenderablesAreCurrent = true
            }
            return sortedRenderables
        }
    }

    private var state = State()

    public var isEmpty: Bool {
        state.renderables.isEmpty
    }

    public func append(_ renderable: Renderable) {
        state.append(renderable)
    }

    public func removeAll(keepingCapacity: Bool = true) {
        state.removeAll(keepingCapacity: keepingCapacity)
    }

    public func getRenderables(sorted: Bool) -> ContiguousArray<Renderable> {
        guard sorted else { return state.renderables }
        return state.sorted()
    }
}
