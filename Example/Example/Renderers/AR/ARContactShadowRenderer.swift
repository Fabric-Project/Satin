//
//  ARContactShadowRenderer.swift
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

fileprivate final class ARObject: Object {
    var anchor: ARAnchor? {
        didSet {
            if let anchor = anchor {
                worldMatrix = anchor.transform
                visible = true
            }
        }
    }

    override init(label: String, visible: Bool = true, _ children: [Object] = []) {
        super.init(label: label, visible: visible, children)
        self.visible = false
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
}

fileprivate final class Invader: Object {
    let voxelScale: Float = 0.025

    let voxels = Object(label: "Voxels")

    override public init() {
        super.init(label: "Invader", [voxels])
        let geometry = BoxGeometry(size: voxelScale)

        let BDY: simd_float4 = [0.0, 1.0, 0.0, 1.0]
        let _E_: simd_float4 = [1.0, 1.0, 1.0, 1.0]

        var materialMap = [simd_float4: Material]()

        let fills: [[simd_float4?]] =
            [
                [nil, nil, BDY, nil, nil, nil, nil, nil, BDY, nil, nil],
                [nil, nil, nil, BDY, nil, nil, nil, BDY, nil, nil, nil],
                [nil, nil, BDY, BDY, BDY, BDY, BDY, BDY, BDY, nil, nil],
                [nil, BDY, BDY, _E_, BDY, BDY, BDY, _E_, BDY, BDY, nil],
                [BDY, BDY, BDY, BDY, BDY, BDY, BDY, BDY, BDY, BDY, BDY],
                [BDY, nil, BDY, BDY, BDY, BDY, BDY, BDY, BDY, nil, BDY],
                [BDY, nil, BDY, nil, nil, nil, nil, nil, BDY, nil, BDY],
                [nil, nil, nil, BDY, BDY, nil, BDY, BDY, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
            ]

        for y in (0 ..< 9).reversed() {
            let row = fills[y]
            for x in 0 ..< 11 {
                if let color = row[x] {
                    var mat: Material?
                    if let existingMaterial = materialMap[color] {
                        mat = existingMaterial
                    } else {
                        let newMaterial = StandardMaterial(baseColor: color, metallic: 0.1, roughness: 0.25)
                        materialMap[color] = newMaterial
                        mat = newMaterial
                    }

                    let voxel = Mesh(geometry: geometry, material: mat!)
                    voxel.position = voxelScale * simd_make_float3(Float(x) - 11.0 / 2.0, 4.0 - Float(y), 0)
                    voxels.add(voxel)
                }
            }
        }

        voxels.position.y = (9.0 * voxelScale) * 0.5 // move the voxels so they are above the ground plane
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
}

final class ARContactShadowRenderer: BaseRenderer {
    var session: ARSession { sessionPublisher.session }
    private let sessionPublisher = ARSessionPublisher(session: ARSession())
    private var anchorsSubscription: AnyCancellable?

    var shadowPlaneMesh = Mesh(
        geometry: PlaneGeometry(size: 1.0, orientation: .zx),
        material: BasicTextureMaterial(texture: nil, flipped: false)
    )

    fileprivate lazy var invaderContainer = ARObject(label: "Invader Container", [invader, shadowPlaneMesh])
    fileprivate var invader = Invader()

    lazy var shadowRenderer = ObjectShadowRenderer(
        context: context,
        object: invader,
        container: invaderContainer,
        scene: scene,
        catcher: shadowPlaneMesh,
        blurRadius: 8.0,
        far: 1.0,
        color: [0.0, 0.0, 0.0, 0.66]
    )

    lazy var scene = Object(label: "Scene", [invaderContainer])
    lazy var context = Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat, depthPixelFormat: .depth32Float)
    lazy var camera = ARPerspectiveCamera(session: session, metalView: metalView, near: 0.01, far: 100.0)
    lazy var renderer = Renderer(context: context)

    var backgroundRenderer: ARBackgroundRenderer!

    lazy var startTime = getTime()

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    override init() {
        super.init()

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        session.run(configuration)
    }

    lazy var lights: [PointLight] = {
        var lights = [PointLight]()
        var positions: [simd_float3] = [[1, 1, 1], [-1, 1, 1], [-1, 1, -1], [1, 1, -1]]
        for position in positions {
            let l = PointLight(color: .one, intensity: 3.0)
            l.position = position
            lights.append(l)
        }
        return lights
    }()

    override func setup() {
        metalView.preferredFramesPerSecond = 60

        invaderContainer.add(lights)

        renderer.colorLoadAction = .load

        backgroundRenderer = ARBackgroundRenderer(
            context: Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat),
            session: session
        )

        anchorsSubscription = sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            guard let self else { return }
            for anchor in anchors {
                if self.invaderContainer.anchor?.identifier == anchor.identifier {
                    self.invaderContainer.anchor = anchor
                    break
                }
            }
        }
    }

    override func update() {
        if invaderContainer.visible {
            let time = Float(getTime() - startTime)
            invader.voxels.orientation = simd_quatf(angle: time, axis: Satin.worldUpDirection)
            invader.voxels.orientation *= simd_quatf(angle: -time * 2.0, axis: Satin.worldRightDirection)
            invader.position.y = remap(sin(time + Float.pi * 0.5), -1.0, 1.0, 0.0, 1.0) * 0.5 + invader.voxelScale
        }

        if let currentFrame = session.currentFrame, let lightEstimate = currentFrame.lightEstimate {
            let ambient = lightEstimate.ambientIntensity / 500.0
            for light in lights {
                light.intensity = Float(ambient)
            }
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        if invaderContainer.visible {
            shadowRenderer.update(commandBuffer: commandBuffer)
        }

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

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
    }

    override func cleanup() {
        session.pause()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: metalView)
        let coordinate = normalizePoint(location, metalView.frame.size)

        let ray = Ray(camera: camera, coordinate: coordinate)
        let query = ARRaycastQuery(origin: ray.origin, direction: ray.direction, allowing: .estimatedPlane, alignment: .horizontal)

        if let result = session.raycast(query).first {
            let anchor = ARAnchor(transform: result.worldTransform)
            session.add(anchor: anchor)

            if let existingAnchor = invaderContainer.anchor {
                session.remove(anchor: existingAnchor)
            }

            invaderContainer.anchor = anchor
        }
    }

    private func normalizePoint(_ point: CGPoint, _ size: CGSize) -> simd_float2 {
#if os(macOS)
        return 2.0 * simd_make_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1.0
#else
        return 2.0 * simd_make_float2(Float(point.x / size.width), 1.0 - Float(point.y / size.height)) - 1.0
#endif
    }
}

#endif
