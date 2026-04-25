//
//  ARPlanesRenderer.swift
//  Example
//
//  Created by Reza Ali on 3/22/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Combine
import Metal

import Satin
import SwiftUI

final class ARPlaneGeometry: Geometry {
    let positionBuffer = Float3BufferAttribute(defaultValue: .zero, data: [])
    let texcoodsBuffer = Float2BufferAttribute(defaultValue: .zero, data: [])
    let indicesBuffer = ElementBuffer(type: .uint16, data: nil, count: 0, source: [])

    var positions = [simd_float3]() {
        didSet {
            positionBuffer.data = positions
        }
    }

    var texcoords = [simd_float2]() {
        didSet {
            texcoodsBuffer.data = texcoords
        }
    }

    var indices = [Int16]() {
        didSet {
            indicesBuffer.updateData(data: &indices, count: indices.count, source: indices)
        }
    }

    public init() {
        super.init()
        addAttribute(positionBuffer, for: .Position)
        addAttribute(texcoodsBuffer, for: .Texcoord)
        setElements(indicesBuffer)
    }
}

final class ARPlaneContainer: Object {
    var anchor: ARPlaneAnchor {
        didSet {
            updateAnchor()
        }
    }

    var geometry = ARPlaneGeometry()
    var planeMesh: Mesh
    var meshWireframe: Mesh

    init(label: String, anchor: ARPlaneAnchor, material: Satin.Material) {
        self.anchor = anchor

        let mat = material.clone()
        mat.set("Color", [Float.random(in: 0 ... 1), Float.random(in: 0 ... 1), Float.random(in: 0 ... 1), 0.25])

        planeMesh = Mesh(geometry: geometry, material: mat)
        meshWireframe = Mesh(geometry: geometry, material: mat)
        meshWireframe.triangleFillMode = .lines
        planeMesh.add(meshWireframe)

        super.init(label: label, [planeMesh])
        updateAnchor()
    }

    required init(from _: Decoder) throws { fatalError("Not implemented") }

    func updateAnchor() {
        updateTransform()
        updateGeometry()
    }

    func updateTransform() {
        worldMatrix = anchor.transform
    }

    func updateGeometry() {
        geometry.positions = anchor.geometry.vertices
        geometry.texcoords = anchor.geometry.textureCoordinates
        geometry.indices = anchor.geometry.triangleIndices
    }
}

final class ARPlanesRenderer: BaseRenderer {
    var session: ARSession { sessionPublisher.session }
    private lazy var sessionPublisher = ARSessionPublisher(session: ARSession())
    private var anchorsAddedSubscription: AnyCancellable?
    private var anchorsUpdatedSubscription: AnyCancellable?

    lazy var planeMaterial: Satin.Material = {
        let material = BasicColorMaterial(color: .one, blending: .additive)
        material.depthWriteEnabled = false
        return material
    }()

    fileprivate var planesMap: [ARAnchor: ARPlaneContainer] = [:]

    // MARK: - 3D

    lazy var scene = Object(label: "Scene")

    lazy var camera = ARPerspectiveCamera(session: session, metalView: metalView, near: 0.01, far: 100.0)
    lazy var renderer = {
        let renderer = Renderer(label: "Content Renderer", context: defaultContext)
        renderer.colorLoadAction = .load
        return renderer
    }()

    // MARK: - Background

    var backgroundRenderer: ARBackgroundRenderer!

    // MARK: - Init

    override init() {
        super.init()

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        session.run(configuration)
    }

    // MARK: - Setup

    override func setup() {
        metalView.preferredFramesPerSecond = 60

        backgroundRenderer = ARBackgroundRenderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat), session: session)

        anchorsAddedSubscription = sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            guard let self else { return }
            for anchor in anchors {
                if self.planesMap[anchor] == nil, let planeAnchor = anchor as? ARPlaneAnchor {
                    let planeContainer = ARPlaneContainer(label: "\(planeAnchor.identifier)", anchor: planeAnchor, material: self.planeMaterial)
                    self.planesMap[anchor] = planeContainer
                    self.scene.add(planeContainer)
                }
            }
        }

        anchorsUpdatedSubscription = sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            guard let self else { return }
            for anchor in anchors {
                if let plane = self.planesMap[anchor], let planeAnchor = anchor as? ARPlaneAnchor {
                    plane.anchor = planeAnchor
                }
            }
        }
    }

    // MARK: - Draw

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
    }

    // MARK: - Cleanup

    override func cleanup() {
        session.pause()
    }

    // MARK: - Resize

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
    }
}
#endif
