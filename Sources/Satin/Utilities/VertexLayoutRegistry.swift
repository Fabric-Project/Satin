//
//  VertexLayoutRegistry.swift
//  Satin
//

import Metal

/// Gives every distinct vertex layout a small integer, so a per-draw pipeline lookup compares
/// integers instead of `MTLVertexDescriptor`s. Descriptors are interned by value: equal layouts share
/// one ID, its position here, for the life of the process. An app draws with a handful of distinct
/// layouts, and a lookup runs only when a geometry hands over a new descriptor object, so the layouts
/// are compared in turn rather than hashed.
enum VertexLayoutRegistry {
    private static let lock = UnfairLock()
    /// Copies, so a later change to a caller's descriptor can't change what an ID stands for.
    private nonisolated(unsafe) static var layouts: [MTLVertexDescriptor] = []

    static func layoutID(for descriptor: MTLVertexDescriptor) -> Int {
        lock.sync {
            if let layoutID = layouts.firstIndex(where: { $0 == descriptor }) { return layoutID }

            layouts.append((descriptor.copy() as? MTLVertexDescriptor) ?? descriptor)
            return layouts.count - 1
        }
    }
}

/// The interned layout ID of the last descriptor object it was asked about. Asking again about the
/// same object costs a pointer compare; a different object is interned again. A descriptor changed
/// in place after it was interned keeps its old ID, so replace a descriptor rather than editing it.
struct InternedVertexLayout {
    private var descriptor: MTLVertexDescriptor?
    private var layoutID = 0

    mutating func layoutID(for descriptor: MTLVertexDescriptor) -> Int {
        if self.descriptor === descriptor { return layoutID }

        layoutID = VertexLayoutRegistry.layoutID(for: descriptor)
        self.descriptor = descriptor
        return layoutID
    }
}
