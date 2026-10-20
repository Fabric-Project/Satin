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
    // TEMPORARY A/B (remove after measuring): false records every caster per face, as before.
    public nonisolated(unsafe) static var recordsCastersOnceForAllFaces = true

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

    /// One caster's recording for this draw, and the faces it may reach.
    private struct CasterRecord {
        let renderable: Renderable
        let packets: Range<Int>
        /// Bit k: the caster may reach face k.
        let faces: UInt8
        /// Whether the one recording encodes correctly as any face's view.
        let servesEveryFace: Bool
    }

    // Reused each draw, keeping capacity.
    private var faceViews: [RenderView] = []
    private var faceFrusta = ContiguousArray<ViewFrustum>()
    private var casterRecords = ContiguousArray<CasterRecord>()

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

    override func draw(context: Context, commandBuffer: MTLCommandBuffer, renderables: ContiguousArray<Renderable>, recorder: PacketRecorder) {
        guard enabled else { return }

        if device == nil {
            device = context.device
        }
        setupTextures()

        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(resolution.width), height: Double(resolution.height), znear: 0.0, zfar: 1.0)
        let viewportFloat4 = simd_make_float4(0.0, 0.0, Float(resolution.width), Float(resolution.height))

        faceViews.removeAll(keepingCapacity: true)
        faceFrusta.removeAll(keepingCapacity: true)
        for camera in cameras {
            let view = RenderView(camera: camera, viewport: viewportFloat4, frame: recorder.frame)
            faceViews.append(view)
            faceFrusta.append(ViewFrustum(viewProjectionMatrix: view.viewProjectionMatrix))
        }
        // Every face's far plane is `far` along its axis: together they bound a cube around the
        // light, and nothing outside it reaches any face.
        let lightPosition = cameras[0].worldPosition
        let reach = simd_float3(repeating: cameras[0].far)
        let faceReach = Bounds(min: lightPosition - reach, max: lightPosition + reach)

        // Each caster is recorded once, for all six faces, and encoded in each face it may reach as
        // that face's view. A caster running custom commands is recorded per face instead: a
        // command may have captured its first view's uniforms.
        casterRecords.removeAll(keepingCapacity: true)
        for renderable in renderables where renderable.castShadow && Self.recordsCastersOnceForAllFaces {
            var faces: UInt8 = 0b11_1111
            if renderable.frustumCulled {
                let bounds = renderable.worldBounds
                faces = 0
                if ViewFrustum.mayIntersect(bounds, faceReach) {
                    for (faceIndex, frustum) in faceFrusta.enumerated() where frustum.mayContain(bounds) {
                        faces |= 1 << faceIndex
                    }
                }
            }
            guard faces != 0 else { continue }

            let packets = recorder.record(renderable, renderContext: context, pass: .shadow, materialPass: .all, views: faceViews)
            casterRecords.append(CasterRecord(
                renderable: renderable,
                packets: packets,
                faces: faces,
                servesEveryFace: recorder.storage.packetsServeEveryView(packets)
            ))
        }

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
            renderEncoderState.begin(renderEncoder: renderEncoder, renderPassDescriptor: renderPassDescriptor)
            renderEncoderState.setPassViewport(viewport)

            if !Self.recordsCastersOnceForAllFaces {
                for renderable in renderables where renderable.castShadow {
                    let packets = recorder.record(renderable, renderContext: context, pass: .shadow, materialPass: .all, views: [faceViews[faceIndex]])
                    recorder.encode(packets, into: renderEncoderState)
                }
            }
            for caster in casterRecords where caster.faces & (1 << faceIndex) != 0 {
                if caster.servesEveryFace {
                    recorder.encode(caster.packets, into: renderEncoderState, viewIndex: faceIndex)
                } else {
                    let packets = recorder.record(caster.renderable, renderContext: context, pass: .shadow, materialPass: .all, views: [faceViews[faceIndex]])
                    recorder.encode(packets, into: renderEncoderState)
                }
            }

            renderEncoder.endEncoding()
            renderEncoderState.end()
        }
        casterRecords.removeAll(keepingCapacity: true)

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
