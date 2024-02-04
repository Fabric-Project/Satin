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
        guard let context = context, let material = material, let parent = parent else { return }
        material.vertexDescriptor = parent.geometry.vertexDescriptor
        material.context = context
    }

    open func setupGeometry() {
        guard let context = context else { return }
        geometry.context = context
    }

    open func bind(renderEncoderState: RenderEncoderState, shadow: Bool) {
        material?.bind(renderEncoderState: renderEncoderState, shadow: shadow)
    }

    open func draw(renderEncoderState: RenderEncoderState, instanceCount: Int) {
        geometry.draw(
            renderEncoderState: renderEncoderState,
            instanceCount: instanceCount,
            indexBufferOffset: indexBufferOffset
        )
    }
}
