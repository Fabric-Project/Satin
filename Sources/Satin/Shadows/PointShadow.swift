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

    override func beginRecording(context: Context) throws {
        prepareForDrawing(context: context)
        if recordedVersion != nil {
            var versions: [MTLTexture?] = []
            for texture in depthTextures {
                guard let texture else { throw SubmissionError.shadowAllocationFailed }
                versions.append(try makeShadowTextureVersion(of: texture, device: context.device))
            }
            depthTextures = versions
            recordedVersion = nil
        }
        recordingState.captureVersion()
    }

    override func adoptRecordedVersion(_ version: RecordedShadow) {
        super.adoptRecordedVersion(version)
        depthTextures = version.textures.map(Optional.some)
    }

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

    override var passCount: Int { 6 }

    override func passCamera(_ passIndex: Int) -> Camera { cameras[passIndex] }

    override func passTexture(_ passIndex: Int) -> MTLTexture? { depthTextures[passIndex] }

    override func prepareForDrawing(context: Context) {
        if device == nil {
            device = context.device
        }
        setupTextures()
    }

    /// Every face's far plane is `far` along its axis: together they bound a cube around the
    /// light, and nothing outside it reaches any face.
    override var reachBounds: Bounds? {
        let lightPosition = cameras[0].worldPosition
        let reach = simd_float3(repeating: cameras[0].far)
        return Bounds(min: lightPosition - reach, max: lightPosition + reach)
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
