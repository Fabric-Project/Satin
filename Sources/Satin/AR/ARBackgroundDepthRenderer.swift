//
//  ARBackgroundDepthRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/11/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Combine
import Foundation

import ARKit
import Metal
import MetalPerformanceShaders

#if SWIFT_PACKAGE
import SatinCore
#endif

public class ARBackgroundDepthRenderer: ARBackgroundRenderer {
    private var sessionPublisher: ARSessionPublisher
    private var sessionSubscriptions = Set<AnyCancellable>()

    private lazy var background = Object(label: "AR Background", [depthMesh, mesh])

    private var depthRenderer: Renderer
    private var depthAnchorPlaneMeshMap: [UUID: ARPlaneMesh] = [:]
    private var depthAnchorLidarMeshMap: [UUID: ARLidarMesh] = [:]

    private var depthScene = Object(label: "Depth Scene")
    private var depthMesh: Mesh
    private var depthCamera: ARPerspectiveCamera

    private var depthUpscaler: ARDepthUpscaler

    private var depthMaterial = {
        let material = BasicColorMaterial(color: [1, 1, 1, 0], blending: .alpha)
        material.depthBias = DepthBias(bias: 5, slope: 5, clamp: 5)
        return material
    }()

    private var depthLidarMaterial = {
        let material = BasicColorMaterial(color: [1, 1, 1, 0], blending: .alpha)
        material.depthBias = DepthBias(bias: 5, slope: 5, clamp: 5)
        return material
    }()

    private let backgroundDepthMaterial = ARBackgroundDepthMaterial()

    public private(set) var sceneDepthTexture: CVMetalTexture? {
        didSet {
            backgroundDepthMaterial.sceneDepthTexture = sceneDepthTexture
        }
    }

    public private(set) var upscaledSceneDepthTexture: MTLTexture? {
        didSet {
            backgroundDepthMaterial.upscaledSceneDepthTexture = upscaledSceneDepthTexture
        }
    }

    override public var colorTexture: MTLTexture? {
        depthRenderer.colorTexture
    }

    public var depthTexture: MTLTexture? {
        depthRenderer.depthTexture
    }

    public var upscaleDepth: Bool
    public var usePlaneDepth: Bool
    public var useMeshDepth: Bool

    public init(
        context: Context,
        session: ARSession,
        sessionPublisher: ARSessionPublisher,
        metalView: MetalView,
        near: Float,
        far: Float,
        upscaleDepth: Bool = true,
        usePlaneDepth: Bool = true,
        useMeshDepth: Bool = true
    ) {
        self.upscaleDepth = upscaleDepth
        self.usePlaneDepth = usePlaneDepth
        self.useMeshDepth = useMeshDepth

        depthRenderer = Renderer(
            label: "AR Background",
            context: context,
            colorLoadAction: .clear,
            colorStoreAction: .store,
            depthLoadAction: .clear,
            depthStoreAction: .store,
            frameBufferOnly: false
        )

        depthCamera = ARPerspectiveCamera(session: session, metalView: metalView, near: near, far: far)

        self.sessionPublisher = sessionPublisher

        backgroundDepthMaterial.set("Near Far Delta", [near, far, far - near])

        depthMesh = Mesh(
            label: "AR Depth Mesh",
            geometry: Geometry(),
            material: backgroundDepthMaterial,
            visible: false
        )

        depthUpscaler = ARDepthUpscaler(device: context.device)

        super.init(context: context, session: session)

        depthCamera.add(background)
        depthScene.attach(background)

        setupSessionSubscriptions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    func update(_ commandBuffer: MTLCommandBuffer) {
        if upscaleDepth,
           let capturedImageTextureY = capturedImageTextureY,
           let yTexture = CVMetalTextureGetTexture(capturedImageTextureY),
           let capturedImageTextureCbCr = capturedImageTextureCbCr,
           let cbcrTexture = CVMetalTextureGetTexture(capturedImageTextureCbCr),
           let depthTexture = sceneDepthTexture,
           let depthTexture = CVMetalTextureGetTexture(depthTexture)
        {
            upscaledSceneDepthTexture = depthUpscaler.update(
                commandBuffer: commandBuffer,
                yTexture: yTexture,
                cbcrTexture: cbcrTexture,
                depthTexture: depthTexture
            )
        }
        else {
            upscaledSceneDepthTexture = nil
        }

        background.scale = [depthCamera.aspect, 1.0, 1.0]
        background.position = [0, 0, -1.0 / tan(degToRad(depthCamera.fov * 0.5))]
    }

    override public func draw(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) {
        update(commandBuffer)

        depthRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: depthScene,
            camera: depthCamera
        )
    }

    override public func draw(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        renderTarget: MTLTexture
    ) {
        update(commandBuffer)

        depthRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: depthScene,
            camera: depthCamera,
            renderTarget: renderTarget
        )
    }

    override public func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        super.resize(size: size, scaleFactor: scaleFactor)
        depthRenderer.resize(size)
    }

    // MARK: - Depth Updates

    override func updateTextures(_ frame: ARFrame) {
        super.updateTextures(frame)
        updateDepthTexture(frame)
    }

    func updateDepthTexture(_ frame: ARFrame) {
        if let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let depthPixelBuffer = sceneDepth.depthMap
            if let depthTexturePixelFormat = getMTLPixelFormat(for: depthPixelBuffer) {
                sceneDepthTexture = createTexture(
                    fromPixelBuffer: depthPixelBuffer,
                    pixelFormat: depthTexturePixelFormat,
                    planeIndex: 0
                )

                depthMesh.visible = true
            }
        }
    }

    override func updateGeometry(_ frame: ARFrame) {
        super.updateGeometry(frame)
        depthMesh.geometry = mesh.geometry
    }

    func getMTLPixelFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat? {
        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32 {
            return .r32Float
        }
        else if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 {
            return .r8Uint
        }
        else {
            return nil
        }
    }

    // MARK: - AR Session

    func setupSessionSubscriptions() {
        sessionPublisher.addedAnchorsPublisher.sink { [weak self] anchors in
            self?.addedAnchors(anchors)
        }.store(in: &sessionSubscriptions)

        sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            self?.updatedAnchors(anchors)
        }.store(in: &sessionSubscriptions)

        sessionPublisher.removedAnchorsPublisher.sink { [weak self] anchors in
            self?.removedAnchors(anchors)
        }.store(in: &sessionSubscriptions)
    }

    func addedAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            if usePlaneDepth, let planeAnchor = anchor as? ARPlaneAnchor {
                let planeMesh = ARPlaneMesh(
                    label: anchor.identifier.uuidString,
                    anchor: planeAnchor,
                    material: depthMaterial
                )
                depthAnchorPlaneMeshMap[anchor.identifier] = planeMesh
                depthScene.add(planeMesh)
            }
            else if useMeshDepth, let meshAnchor = anchor as? ARMeshAnchor {
                let lidarMesh = ARLidarMesh(meshAnchor: meshAnchor, material: depthLidarMaterial)
                depthAnchorLidarMeshMap[anchor.identifier] = lidarMesh
                depthScene.add(lidarMesh)
            }
        }
    }

    func updatedAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            if usePlaneDepth, let planeAnchor = anchor as? ARPlaneAnchor {
                if let planeMesh = depthAnchorPlaneMeshMap[anchor.identifier] {
                    planeMesh.anchor = planeAnchor
                }
            }
            else if useMeshDepth, let meshAnchor = anchor as? ARMeshAnchor {
                if let lidarMesh = depthAnchorLidarMeshMap[anchor.identifier] {
                    lidarMesh.meshAnchor = meshAnchor
                }
            }
        }
    }

    func removedAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            if usePlaneDepth, let planeAnchor = anchor as? ARPlaneAnchor {
                if let mesh = depthAnchorPlaneMeshMap.removeValue(forKey: planeAnchor.identifier) {
                    depthScene.remove(mesh)
                }
            }
            else if useMeshDepth, let meshAnchor = anchor as? ARMeshAnchor {
                if let mesh = depthAnchorLidarMeshMap.removeValue(forKey: meshAnchor.identifier) {
                    depthScene.remove(mesh)
                }
            }
        }
    }
}

#endif
