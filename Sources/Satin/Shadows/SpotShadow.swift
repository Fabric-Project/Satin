//
//  SpotShadow.swift
//  Satin
//
//  Created by OpenAI on 4/19/26.
//

import Combine
import Foundation
import Metal
import simd

public final class SpotShadow: Shadow {
    var device: MTLDevice? {
        didSet {
            if device != nil {
                setupTexture()
            }
        }
    }

    private var _updateTexture = true

    override public var resolution: (width: Int, height: Int) {
        didSet {
            if resolution.width != oldValue.width || resolution.height != oldValue.height {
                _updateTexture = true
                needsUpdate = true
                resolutionPublisher.send(self)
            }
        }
    }

    override public var strength: Float {
        didSet {
            if strength != oldValue {
                dataPublisher.send(self)
            }
        }
    }

    override public var radius: Float {
        didSet {
            if radius != oldValue {
                dataPublisher.send(self)
            }
        }
    }

    override public var bias: Float {
        didSet {
            if bias != oldValue {
                dataPublisher.send(self)
            }
        }
    }

    override public var normalBias: Float {
        didSet {
            if normalBias != oldValue {
                dataPublisher.send(self)
            }
        }
    }

    override public var texture: MTLTexture? {
        didSet {
            texturePublisher.send(self)
        }
    }

    override public init(context: Context, label: String) {
        super.init(context: context, label: label)
        camera = PerspectiveCamera(context: context, label: "\(label) Camera", position: .zero, near: 0.01, far: 100.0, fov: 90.0)
    }

    private var viewport: MTLViewport {
        MTLViewport(originX: 0, originY: 0, width: Double(resolution.width), height: Double(resolution.height), znear: 0.0, zfar: 1.0)
    }

    private var viewportFloat4: simd_float4 {
        simd_make_float4(0.0, 0.0, Float(resolution.width), Float(resolution.height))
    }

    override public func update(light: Object) {
        guard let light = light as? SpotLight, let camera = camera as? PerspectiveCamera else {
            needsUpdate = true
            return
        }

        camera.position = light.renderSnapshotWorldPosition
        camera.lookAt(target: light.renderSnapshotWorldPosition + light.renderSnapshotWorldForwardDirection, up: Satin.worldUpDirection)
        camera.aspect = 1.0
        camera.fov = light.renderSnapshotAngleOuter * 2.0
        camera.near = 0.01
        camera.far = max(light.renderSnapshotRadius, camera.near + 0.01)
        camera.refreshRenderState()

        needsUpdate = true
    }

    override public func draw(context: Context, commandBuffer: MTLCommandBuffer, renderables: [Renderable]) {
        guard enabled else { return }

        if device == nil {
            device = context.device
        }
        setupTexture()

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.defaultRasterSampleCount = context.sampleCount
        renderPassDescriptor.depthAttachment.texture = texture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .store
        renderPassDescriptor.depthAttachment.clearDepth = 0.0
        renderPassDescriptor.renderTargetWidth = resolution.width
        renderPassDescriptor.renderTargetHeight = resolution.height

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        renderEncoder.label = label + " Shadow Encoder"
        renderEncoder.setViewport(viewport)

        let renderEncoderState = RenderEncoderState(renderEncoder: renderEncoder)
        for renderable in renderables where renderable.isDrawable(renderContext: context, shadow: true) && renderable.castShadow {
            renderable.update(renderContext: context, camera: camera, viewport: viewportFloat4, index: 0)
            renderEncoderState.cullMode = renderable.cullMode
            renderEncoderState.windingOrder = renderable.windingOrder
            renderEncoderState.triangleFillMode = renderable.triangleFillMode
            renderable.draw(renderContext: context, renderEncoderState: renderEncoderState, shadow: true)
        }

        renderEncoder.endEncoding()
        needsUpdate = false
    }

    private func setupTexture() {
        guard let device, _updateTexture, resolution.width > 1, resolution.height > 1 else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: resolution.width, height: resolution.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate
        texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label + " Depth Texture"
        _updateTexture = false
    }
}
