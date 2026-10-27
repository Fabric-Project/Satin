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

    override public func update(light: Object) {
        guard let light = light as? SpotLight, let camera = camera as? PerspectiveCamera else {
            needsUpdate = true
            return
        }

        camera.position = light.worldPosition
        camera.lookAt(target: light.worldPosition + light.worldForwardDirection, up: Satin.worldUpDirection)
        camera.aspect = 1.0
        camera.fov = light.angleOuter * 2.0
        camera.near = 0.01
        camera.far = max(light.radius, camera.near + 0.01)

        needsUpdate = true
    }

    override func prepareForDrawing(context: Context) {
        if device == nil {
            device = context.device
        }
        setupTexture()
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
