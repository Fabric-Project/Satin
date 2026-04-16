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

    weak var parent: Mesh?
    var material: Material?
    var geometry = Geometry()

    public init(
        context: Context,
        label: String = "Submesh",
        parent: Mesh,
        elementBuffer: ElementBuffer,
        indexBufferOffset: Int = 0,
        material: Material? = nil
    ) {
        self.context = context
        self.parent = parent
        self.indexBufferOffset = indexBufferOffset
        self.material = material
        geometry.setElements(elementBuffer)
    }

    public convenience init(
        label: String = "Submesh",
        parent: Mesh,
        elementBuffer: ElementBuffer,
        indexBufferOffset: Int = 0,
        material: Material? = nil
    ) {
        guard let context = parent.context else {
            preconditionFailure("Submesh requires a parent mesh with a bound context")
        }
        self.init(
            context: context,
            label: label,
            parent: parent,
            elementBuffer: elementBuffer,
            indexBufferOffset: indexBufferOffset,
            material: material
        )
    }

    open func setup() {
        setupMaterial()
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

    open func setupMaterial() {
        guard let material, let parent else { return }
        material.vertexDescriptor = parent.geometry.vertexDescriptor
        material.bindContext(context)
    }

    open func setupGeometry() {
        geometry.bindContext(context)
    }

    func bindContext(_ newContext: Context) {
        precondition(
            context == newContext,
            "\(type(of: self)) expected matching context. Existing: \(context.id), new: \(newContext.id)"
        )
    }

    open func draw(renderContext: Context, renderEncoderState: RenderEncoderState, instanceCount: Int, shadow: Bool) {
        material?.bind(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )
        geometry.draw(
            renderEncoderState: renderEncoderState,
            instanceCount: instanceCount,
            indexBufferOffset: indexBufferOffset
        )
    }
}
