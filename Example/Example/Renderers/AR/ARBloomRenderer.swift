//
//  ARGlowRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/26/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Combine
import Metal
import MetalKit
import Satin

final class ARBloomRenderer: BaseRenderer {
    final class BloomMaterial: SourceMaterial {
        public var grainIntensity: Float = 0.0 {
            didSet {
                set("Grain Intensity", grainIntensity)
            }
        }

        public var time: Float = 0.0 {
            didSet {
                set("Time", time)
            }
        }

        public var bloomTexture: MTLTexture? {
            didSet {
                set(bloomTexture, index: FragmentTextureIndex.Custom0)
            }
        }

        public var grainTexture: MTLTexture? {
            didSet {
                set(grainTexture, index: FragmentTextureIndex.Custom1)
            }
        }
    }

    // MARK: - UI

    override var paramKeys: [String] {
        ["Post Material"]
    }

    override var params: [String: ParameterGroup?] {
        ["Post Material": postMaterial.parameters]
    }

    // MARK: - Glow Blur

    lazy var bloomGenerator = BloomGenerator(device: device, levels: 6)

    // MARK: - AR

    let session = ARSession()
    lazy var sessionPublisher = ARSessionPublisher(session: session)
    var sessionSubscriptions = Set<AnyCancellable>()

    let geometry = IcoSphereGeometry(radius: 0.1, resolution: 3)

    var occlusionMaterial = {
        let material = BasicColorMaterial(color: [1, 1, 1, 0], blending: .disabled)
        material.depthBias = DepthBias(bias: 10.0, slope: 10.0, clamp: 10.0)
        return material
    }()

    var objectAnchorMap: [UUID: Object] = [:]
    var scene = Object(label: "Scene")

    lazy var context = Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat, depthPixelFormat: .depth32Float)
    lazy var camera = ARPerspectiveCamera(session: session, metalView: metalView, near: 0.01, far: 100.0)
    lazy var renderer = Renderer(
        label: "Renderer",
        context: context,
        colorLoadAction: .load,
        depthLoadAction: .load
    )

    // handles depth (lidar depth map, lidar mesh & horizontal & vertical planes)
    var backgroundRenderer: ARBackgroundDepthRenderer!

    lazy var bloomRenderer = Renderer(
        label: "Bloom Renderer",
        context: context,
        clearColor: .zero,
        depthLoadAction: .load,
        depthStoreAction: .store,
        frameBufferOnly: false
    )

    let bloomedScene = Object(label: "Bloomed Objects")

    lazy var startTime = getTime()

    lazy var postMaterial: BloomMaterial = {
        let material = BloomMaterial(pipelinesURL: pipelinesURL)
        material.depthWriteEnabled = false
        material.blending = .additive
        return material
    }()

    lazy var postProcessor = PostProcessor(
        label: "Bloom Post Processor",
        context: Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat),
        material: postMaterial
    )

    override init() {
        super.init()
        let configuration = ARWorldTrackingConfiguration()
        // ARBackgroundDepthRenderer supports:
        configuration.frameSemantics = .smoothedSceneDepth
        // and/or configuration.planeDetection = [.horizontal, .vertical]
        // and/or configuration.sceneReconstruction = .mesh
        session.run(configuration)
    }

    override func setup() {
        setupSessionObservers()

        geometry.context = context

        backgroundRenderer = ARBackgroundDepthRenderer(
            context: context,
            session: session,
            sessionPublisher: sessionPublisher,
            metalView: metalView,
            near: camera.near,
            far: camera.far
        )
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        backgroundRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        let brpd = MTLRenderPassDescriptor()
        brpd.depthAttachment.texture = renderPassDescriptor.depthAttachment.texture
        bloomRenderer.draw(
            renderPassDescriptor: brpd,
            commandBuffer: commandBuffer,
            scene: bloomedScene,
            camera: camera
        )

        if let colorTexture = bloomRenderer.colorTexture {
            postMaterial.bloomTexture = bloomGenerator.encode(commandBuffer: commandBuffer, sourceTexture: colorTexture)
        }

        postMaterial.grainTexture = session.currentFrame?.cameraGrainTexture
        postMaterial.grainIntensity = session.currentFrame?.cameraGrainIntensity ?? 0
        postMaterial.time = Float(getTime() - startTime)

        postProcessor.renderer.colorLoadAction = .load

        postProcessor.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
        bloomRenderer.resize(size)
        postProcessor.resize(size: size, scaleFactor: scaleFactor)
    }

    override func cleanup() {
        session.pause()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        let location = touch.location(in: metalView)
        let coordinate = normalizePoint(location, metalView.frame.size)

        let result = raycast(ray: Ray(camera: camera, coordinate: coordinate), object: scene)
        if let first = result.first?.object {
            if bloomedScene.children.contains(first) {
                bloomedScene.remove(first)
            } else {
                bloomedScene.attach(first)
            }
        } else if let currentFrame = session.currentFrame {
            let anchor = ARAnchor(transform: simd_mul(currentFrame.camera.transform, translationMatrixf(0.0, 0.0, -0.25)))
            session.add(anchor: anchor)

            let mesh = Mesh(
                geometry: geometry,
                material: BasicColorMaterial(color: simd_float4(.random(in: 0.25 ... 1), 0.8), blending: .alpha)
            )
            mesh.doubleSided = true
            mesh.cullMode = .none
            mesh.scale = .init(repeating: .random(in: 0.25 ... 1.0))

            let object = Object(label: anchor.identifier.uuidString, [mesh])

            scene.attach(object)
            object.worldMatrix = anchor.transform
            objectAnchorMap[anchor.identifier] = object
        }
    }

    // MARK: - Internal Methods

    func setupSessionObservers() {
        sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            guard let self = self else { return }
            for anchor in anchors {
                if let object = objectAnchorMap[anchor.identifier] {
                    object.worldMatrix = anchor.transform
                }
            }
        }.store(in: &sessionSubscriptions)
    }

    private func normalizePoint(_ point: CGPoint, _ size: CGSize) -> simd_float2 {
#if os(macOS)
        return 2.0 * simd_make_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1.0
#else
        return 2.0 * simd_make_float2(Float(point.x / size.width), 1.0 - Float(point.y / size.height)) - 1.0
#endif
    }

    func createTexture(_ label: String, _ pixelFormat: MTLPixelFormat, _ textureScale: Int) -> MTLTexture? {
        if metalView.drawableSize.width > 0, metalView.drawableSize.height > 0 {
            let descriptor = MTLTextureDescriptor()
            descriptor.pixelFormat = pixelFormat
            descriptor.width = Int(metalView.drawableSize.width) / textureScale
            descriptor.height = Int(metalView.drawableSize.height) / textureScale
            descriptor.sampleCount = 1
            descriptor.textureType = .type2D
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            descriptor.resourceOptions = .storageModePrivate
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            texture.label = label
            return texture
        }
        return nil
    }
}

#endif
