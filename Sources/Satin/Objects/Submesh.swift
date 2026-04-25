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
    open var context: Context? {
        didSet {
            if context != nil, context != oldValue {
                setup()
            }
        }
    }

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
        label: String = "Submesh",
        parent: Mesh,
        elementBuffer: ElementBuffer,
        indexBufferOffset: Int = 0,
        material: Material? = nil
    ) {
        self.parent = parent
        self.indexBufferOffset = indexBufferOffset
        self.material = material
        geometry.setElements(elementBuffer)
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
        guard let context, let material, let parent else { return }
        material.vertexDescriptor = parent.geometry.vertexDescriptor
        material.context = context
    }

    open func setupGeometry() {
        guard let context else { return }
        geometry.context = context
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
