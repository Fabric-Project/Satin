//
//  PointShadow.swift
//  Satin
//
//  Created by OpenAI on 4/19/26.
//

import Combine
import Foundation
import Metal
import simd

public final class PointShadow: Shadow {
    var device: MTLDevice? {
        didSet {
            if device != nil {
                setupTextures()
            }
        }
    }

    private let cameras: [PerspectiveCamera]
    private var depthTextures: [MTLTexture?] = Array(repeating: nil, count: 6)
    private var updateTextures = true

    private let faceDirections: [(direction: simd_float3, up: simd_float3)] = [
        (Satin.worldRightDirection, Satin.worldUpDirection),
        (-Satin.worldRightDirection, Satin.worldUpDirection),
        (Satin.worldUpDirection, -Satin.worldForwardDirection),
        (-Satin.worldUpDirection, Satin.worldForwardDirection),
        (Satin.worldForwardDirection, Satin.worldUpDirection),
        (-Satin.worldForwardDirection, Satin.worldUpDirection),
    ]

    override public var textures: [MTLTexture] {
        depthTextures.compactMap { $0 }
    }

    override public var matrices: [simd_float4x4] {
        cameras.map(\.viewProjectionMatrix)
    }

    override public var viewCount: Int {
        6
    }

    override public var resolution: (width: Int, height: Int) {
        didSet {
            if resolution.width != oldValue.width || resolution.height != oldValue.height {
                updateTextures = true
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

    override public init(context: Context, label: String) {
        cameras = (0..<6).map { index in
            PerspectiveCamera(context: context, label: "\(label) Camera \(index)", position: .zero, near: 0.01, far: 100.0, fov: 90.0)
        }
        super.init(context: context, label: label)
        camera = cameras[0]
    }

    override public func update(light: Object) {
        guard let light = light as? PointLight else {
            needsUpdate = true
            return
        }

        for (index, camera) in cameras.enumerated() {
            camera.position = light.worldPosition
            camera.lookAt(target: light.worldPosition + faceDirections[index].direction, up: faceDirections[index].up)
            camera.aspect = 1.0
            camera.fov = 90.0
            camera.near = 0.01
            camera.far = max(light.radius, camera.near + 0.01)
        }

        needsUpdate = true
    }

    override public func draw(context: Context, commandBuffer: MTLCommandBuffer, renderables: [Renderable]) {
        guard enabled else { return }

        if device == nil {
            device = context.device
        }
        setupTextures()

        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(resolution.width), height: Double(resolution.height), znear: 0.0, zfar: 1.0)
        let viewportFloat4 = simd_make_float4(0.0, 0.0, Float(resolution.width), Float(resolution.height))

        for (faceIndex, faceTexture) in depthTextures.enumerated() {
            guard let faceTexture else { continue }

            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.defaultRasterSampleCount = context.sampleCount
            renderPassDescriptor.depthAttachment.texture = faceTexture
            renderPassDescriptor.depthAttachment.loadAction = .clear
            renderPassDescriptor.depthAttachment.storeAction = .store
            renderPassDescriptor.depthAttachment.clearDepth = 0.0
            renderPassDescriptor.renderTargetWidth = resolution.width
            renderPassDescriptor.renderTargetHeight = resolution.height

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { continue }

            renderEncoder.label = "\(label) Shadow Encoder \(faceIndex)"
            renderEncoder.setViewport(viewport)

            let renderEncoderState = RenderEncoderState(renderEncoder: renderEncoder)
            let camera = cameras[faceIndex]
            for renderable in renderables where renderable.isDrawable(renderContext: context, shadow: true) && renderable.castShadow {
                renderable.update(renderContext: context, camera: camera, viewport: viewportFloat4, index: 0)
                renderEncoderState.cullMode = renderable.cullMode
                renderEncoderState.windingOrder = renderable.windingOrder
                renderEncoderState.triangleFillMode = renderable.triangleFillMode
                renderable.draw(renderContext: context, renderEncoderState: renderEncoderState, shadow: true)
            }

            renderEncoder.endEncoding()
        }

        needsUpdate = false
    }

    private func setupTextures() {
        guard let device, updateTextures, resolution.width > 1, resolution.height > 1 else { return }

        depthTextures = (0..<6).map { face in
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: resolution.width, height: resolution.height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            descriptor.resourceOptions = .storageModePrivate
            let texture = device.makeTexture(descriptor: descriptor)
            texture?.label = "\(label) Depth Texture \(face)"
            return texture
        }

        updateTextures = false
        texturePublisher.send(self)
    }
}
