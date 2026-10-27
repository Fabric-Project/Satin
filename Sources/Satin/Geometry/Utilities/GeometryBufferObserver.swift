//
//  GeometryBufferObserver.swift
//  Satin
//

/// Carries a buffer's change notifications to the geometry using it. Each geometry owns one, and
/// every buffer the geometry uses holds it strongly, so no buffer references a geometry weakly: a
/// weak reference would put the geometry's reference counting on Swift's slow path for its life.
///
/// The back pointer is checked `unowned`: it costs no side table, and a broken contract traps
/// instead of reading freed memory. The geometry unregisters from each buffer the moment it stops
/// using it and clears `geometry` in its deinit, so a buffer that outlives it holds no observer.
/// Buffers notify on the thread that changes them, which must be the thread that owns their
/// geometries.
final class GeometryBufferObserver {
    unowned var geometry: Geometry?

    init(geometry: Geometry) {
        self.geometry = geometry
    }
}

/// The observers of one buffer: the geometries using it, each registered once.
struct GeometryBufferObservers {
    private(set) var observers: [GeometryBufferObserver] = []

    var count: Int { observers.count }

    mutating func add(_ observer: GeometryBufferObserver) {
        for existing in observers where existing === observer { return }
        observers.append(observer)
    }

    mutating func remove(_ observer: GeometryBufferObserver) {
        for index in observers.indices where observers[index] === observer {
            observers.remove(at: index)
            return
        }
    }

    func notifyVertexDataChanged() {
        for observer in observers {
            observer.geometry?.vertexDataChanged()
        }
    }

    func notifyIndexDataChanged() {
        for observer in observers {
            observer.geometry?.indexDataChanged()
        }
    }
}
