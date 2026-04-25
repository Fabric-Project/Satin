//
//  ARPeopleOcclusionRenderer.swift
//  AR
//
//  Created by Reza Ali on 9/26/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Combine
import Metal

import Satin

final class ARPeopleOcclusionRenderer: BaseRenderer {
    var session: ARSession { sessionPublisher.session }
    private lazy var sessionPublisher = ARSessionPublisher(session: ARSession())
    private var anchorsUpdatedSubscription: AnyCancellable?

    let boxGeometry = BoxGeometry(size: 0.1)
    let boxMaterial = UVColorMaterial()

    var meshAnchorMap: [UUID: Mesh] = [:]

    var scene = Object(label: "Scene")

    lazy var camera = ARPerspectiveCamera(session: session, metalView: metalView, near: 0.001, far: 100.0)
    lazy var renderer = Renderer(context: defaultContext, clearColor: .zero, frameBufferOnly: false)

    var backgroundRenderer: ARBackgroundRenderer!
    var matteRenderer: ARMatteRenderer!

    var backgroundTexture: MTLTexture?
    var _updateTextures = true

    var compositor: ARCompositor!

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    override init() {
        super.init()

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.personSegmentationWithDepth]
        session.run(config)
    }

    override func setup() {
        metalView.preferredFramesPerSecond = 60

        backgroundRenderer = ARBackgroundRenderer(
            context: Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat),
            session: session
        )

        matteRenderer = ARMatteRenderer(
            device: device,
            session: session,
            matteResolution: .full,
            near: camera.near,
            far: camera.far
        )

        compositor = ARCompositor(
            label: "AR Compositor",
            context: Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat),
            session: session
        )

        anchorsUpdatedSubscription = sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            guard let self else { return }
            for anchor in anchors {
                if let mesh = self.meshAnchorMap[anchor.identifier] {
                    mesh.worldMatrix = anchor.transform
                }
            }
        }
    }

    override func update() {
        if _updateTextures {
            backgroundTexture = createTexture("Background Texture", colorPixelFormat)
            _updateTextures = false
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        matteRenderer.encode(commandBuffer: commandBuffer)

        if let backgroundTexture = backgroundTexture {
            backgroundRenderer.draw(
                renderPassDescriptor: MTLRenderPassDescriptor(),
                commandBuffer: commandBuffer,
                renderTarget: backgroundTexture
            )
        }

        renderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        compositor.backgroundTexture = backgroundTexture
        compositor.contentTexture = renderer.colorTexture
        compositor.depthTexture = renderer.depthTexture
        compositor.alphaTexture = matteRenderer.alphaTexture
        compositor.dilatedDepthTexture = matteRenderer.dilatedDepthTexture

        compositor.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
        compositor.resize(size: size, scaleFactor: scaleFactor)
        matteRenderer.resize(size)

        _updateTextures = true
    }

    override func cleanup() {
        session.pause()
    }

    override func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
        if let currentFrame = session.currentFrame {
            let anchor = ARAnchor(transform: simd_mul(currentFrame.camera.transform, translationMatrixf(0.0, 0.0, -0.25)))
            session.add(anchor: anchor)
            let mesh = Mesh(geometry: boxGeometry, material: boxMaterial)
            mesh.worldMatrix = anchor.transform
            meshAnchorMap[anchor.identifier] = mesh
            scene.add(mesh)
        }
    }

    func createTexture(_ label: String, _ pixelFormat: MTLPixelFormat) -> MTLTexture? {
        if metalView.drawableSize.width > 0, metalView.drawableSize.height > 0 {
            let descriptor = MTLTextureDescriptor()
            descriptor.pixelFormat = pixelFormat
            descriptor.width = Int(metalView.drawableSize.width)
            descriptor.height = Int(metalView.drawableSize.height)
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
