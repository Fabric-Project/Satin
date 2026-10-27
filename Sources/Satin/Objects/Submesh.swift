//
//  Submesh.swift
//  Satin
//
//  Created by Reza Ali on 5/25/20.
//

import Combine
import Metal
import simd

open class Submesh {
    public var id: String = UUID().uuidString
    public var label = "Submesh"
    public private(set) var context: Context

    public var visible = true
    public var indexBufferOffset = 0
    public var elementBuffer: ElementBuffer? {
        geometry.elementBuffer
    }

    private var _updateIndexBuffer = true

    var material: Material?
    /// Its indices: an elements-only geometry drawn over the mesh's vertices.
    let geometry: Geometry

    /// A range of indices into the vertices of the mesh it is added to, drawn with its own material.
    /// The mesh passes its vertex geometry and draw layout in, so a submesh keeps no reference to it.
    public init(
        context: Context,
        label: String = "Submesh",
        elementBuffer: ElementBuffer,
        indexBufferOffset: Int = 0,
        material: Material? = nil
    ) {
        self.context = context
        self.label = label
        self.indexBufferOffset = indexBufferOffset
        self.material = material
        geometry = Geometry(context: context)
        geometry.setElements(elementBuffer)
    }

    /// Sets this submesh up to draw the vertices of `vertexGeometry`, its mesh's geometry.
    open func setup(vertexGeometry: Geometry) {
        setupMaterial(vertexGeometry: vertexGeometry)
        setupGeometry()
    }

    open func update() {
        material?.update()
        geometry.update()
    }

    open func encode(in context: EncodingContext) throws {
        try material?.encode(in: context)
        try geometry.encode(in: context)
    }

    open func setupMaterial(vertexGeometry: Geometry) {
        guard let material else { return }
        material.vertexDescriptor = vertexGeometry.vertexDescriptor
        material.tessellationDescriptor = vertexGeometry.tessellationDescriptor
        material.setup()
    }

    open func setupGeometry() {}
}
