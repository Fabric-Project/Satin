//
//  Renderable.swift
//
//
//  Created by Reza Ali on 4/19/22.
//

import Combine
import Metal
import simd

open class Renderable : Object {

    open var opaque: Bool { material!.blending == .disabled }
    
    final let doubleSidedPublisher = PassthroughSubject<Bool, Never>()
    open var doubleSided: Bool = false {
        didSet {
            doubleSidedPublisher.send(doubleSided)
        }
    }

    final let renderOrderPublisher = PassthroughSubject<Int, Never>()
    open var renderOrder = 0 {
        didSet {
            renderOrderPublisher.send(renderOrder)
        }
    }

    final let renderPassPublisher = PassthroughSubject<Int, Never>()
    open var renderPass = 0 {
        didSet {
            renderPassPublisher.send(renderPass)
        }
    }
    
    open var lighting: Bool { material?.lighting ?? false }


    final let receiveShadowPublisher = PassthroughSubject<Bool, Never>()
    open var receiveShadow = false {
        didSet {
            receiveShadowPublisher.send(receiveShadow)
        }
    }

    final let castShadowPublisher = PassthroughSubject<Bool, Never>()
    open var castShadow = false {
        didSet {
            castShadowPublisher.send(castShadow)
        }
    }


    final let cullModePublisher = PassthroughSubject<MTLCullMode, Never>()
    open var cullMode: MTLCullMode = .back {
        didSet {
            cullModePublisher.send(cullMode)
        }
    }

    open var windingOrder: MTLWinding = .counterClockwise
    
    final let triangleFillModePublisher = PassthroughSubject<MTLTriangleFillMode, Never>()
    open var triangleFillMode: MTLTriangleFillMode = .fill {
        didSet {
            triangleFillModePublisher.send(triangleFillMode)
        }
    }
    
    open var vertexUniforms: [Context: VertexUniformBuffer] = [:]

    open var material: Material? = nil
    open var materials: [Material] = []

    open var preDraw: ((_ renderEncoder: MTLRenderCommandEncoder) -> Void)? = nil

    open func isDrawable(renderContext: Context, shadow: Bool) -> Bool {
        fatalError("Subclasses must implement this method")
    }
    
//    func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int) {
//        fatalError("Subclasses must implement this method")
//    }

    open func draw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        fatalError("Subclasses must implement this method")
    }
}
