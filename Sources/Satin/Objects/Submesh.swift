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
    var geometry: Geometry!

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

    open func encode(_ commandBuffer: MTLCommandBuffer) {
        material?.encode(commandBuffer)
        geometry.encode(commandBuffer)
    }

    open func setupMaterial(vertexGeometry: Geometry) {
        guard let material else { return }
        material.vertexDescriptor = vertexGeometry.vertexDescriptor
        material.tessellationDescriptor = vertexGeometry.tessellationDescriptor
        material.setup()
    }

    open func setupGeometry() {}

    /// Records this submesh's material and draw call; its mesh has recorded the shared vertex
    /// uniforms and vertex buffers, and passes the layout they need.
    open func draw(in context: RenderableDrawContext, instanceCount: Int, layout: DrawLayout) {
        // The material may be shared with meshes of another layout: pick the pipeline for ours.
        material?.draw(in: context.materialContext(layout: layout))
        geometry.recordDrawCall(in: context.geometryContext(instanceCount: instanceCount, indexBufferOffset: indexBufferOffset))
    }
}
