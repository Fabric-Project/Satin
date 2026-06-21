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
    enum MaterialPass {
        case all
        case opaque
        case alphaTransparent
        case classicTransparent
        case surfaceOpaque
        case unlitOpaque
    }

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

    final let renderLayerPublisher = PassthroughSubject<RenderLayer, Never>()
    open var renderLayer: RenderLayer = .opaque {
        didSet {
            renderLayerPublisher.send(renderLayer)
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
    
    open var vertexUniforms: [UUID: VertexUniformBuffer] = [:]
    var materialPass: MaterialPass = .all

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

    /// Prepares this renderable to be encoded `count` times in a single render pass.
    /// Expands all ring buffers (vertex uniforms, material uniforms, geometry) so that
    /// each encoding sees independent data. Call once before the iteration loop begins,
    /// whenever `count` or the set of child renderables changes.
    open func prepareForRepeatedEncoding(count: Int) {
        // Default: no-op. Mesh and InstancedMesh provide implementations.
    }

    open func selectRepeatedEncodingSlot(iteration: Int, count: Int) {
        // Default: no-op. Mesh and InstancedMesh provide implementations.
    }
}
