//
//  ParametricSurfacesRenderer.swift
//  Example
//
//  Created by OpenAI Codex on 6/3/26.
//

import Combine
import Metal
import MetalKit
import Satin

final class ParametricSurfacesRenderer: BaseRenderer {
    enum SurfaceOption: String, CaseIterable {
        case mobiusStrip = "Mobius Strip"
        case helicoid = "Helicoid"
        case superellipsoid = "Superellipsoid"
        case kleinBottle = "Klein Bottle"
        case catenoid = "Catenoid"
        case paraboloid = "Paraboloid"
        case enneperSurface = "Enneper Surface"
        case pseudosphere = "Pseudosphere"
        case dupinCyclide = "Dupin Cyclide"
        case romanSurface = "Roman Surface"
        case crossCap = "Cross-Cap"
        case bourSurface = "Bour Surface"
        case breatherSurface = "Breather Surface"
        case diniSurface = "Dini Surface"

        static func from(title: String) -> SurfaceOption {
            SurfaceOption(rawValue: title) ?? .mobiusStrip
        }
    }

    struct SurfacePresentation {
        let geometry: Geometry
        let scale: simd_float3
        let position: simd_float3
        let orientation: simd_quatf
    }

    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    let surfaceParam = StringParameter(
        "Surface",
        SurfaceOption.mobiusStrip.rawValue,
        SurfaceOption.allCases.map(\.rawValue),
        .dropdown
    )

    lazy var parameters = ParameterGroup("Parametric Surface", [surfaceParam])

    private var parameterSubscription: AnyCancellable?
    private var baseOrientation = simd_quatf(angle: 0.0, axis: Satin.worldUpDirection)

    lazy var surfaceMaterial: Material = {
//        NormalColorMaterial(context: defaultContext, true)
        StandardMaterial(context: defaultContext, baseColor: [0.82, 0.84, 0.88, 1.0], metallic: 0.8, roughness: 0.2, specular: 1.0, )
    }()

    lazy var cycloramaMesh = Mesh(
        context: defaultContext,
        geometry: CycloramaGeometry(
            context: defaultContext,
            width: 14.0,
            length: 10.0,
            depth: 8.0,
            radius: 2.4,
            widthResolution: 6,
            lengthResolution: 6,
            depthResolution: 5,
            angularResolution: 24
        ),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.82, 0.84, 0.88, 1.0],
            metallic: 0.0,
            roughness: 0.97
        )
    )

    lazy var mesh = Mesh(
        context: defaultContext,
        label: "Parametric Surface",
        geometry: makePresentation(for: .mobiusStrip).geometry,
        material: surfaceMaterial
    )

    lazy var light0 = DirectionalLight(context: defaultContext, color: [1.0, 0.97, 0.94], intensity: 1.0)
    lazy var light1 = DirectionalLight(context: defaultContext, color: [0.72, 0.82, 1.0], intensity: 0.45)

    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [light0, light1, cycloramaMesh, mesh])
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 1.25, 7.5], near: 0.01, far: 200.0, fov: 32.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)
    lazy var startTime = getTime()

    var availableSurfaces: [String] { surfaceParam.options }

    override func setup() {
        renderer.clearColor = .init(red: 0.1, green: 0.11, blue: 0.13, alpha: 1.0)

        cycloramaMesh.label = "Cyclorama"
        cycloramaMesh.position = [0.0, -2.25, -4.25]
        cycloramaMesh.receiveShadow = true
        cycloramaMesh.cullMode = .none

        mesh.cullMode = .none
        mesh.castShadow = true
        mesh.receiveShadow = true

        light0.position = [4.0, 5.5, 5.0]
        light0.lookAt(target: [0.0, 0.45, 0.0], up: Satin.worldUpDirection)
        light0.castShadow = true

        light1.position = [-3.5, 3.5, 2.0]
        light1.lookAt(target: [0.0, 0.2, 0.0], up: Satin.worldUpDirection)
        light1.castShadow = true

        parameterSubscription = surfaceParam.valuePublisher.sink { [weak self] value in
            self?.applySurface(named: value)
        }

        loadHdri()
        applySurface(named: surfaceParam.value)
        camera.lookAt(target: [0.0, 0.4, 0.0])

#if os(visionOS)
        metalView.backgroundColor = .clear
#endif
    }

    func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
            scene.environmentIntensity = 0.05
        }
    }

    func makePresentation(for option: SurfaceOption) -> SurfacePresentation {
        switch option {
        case .mobiusStrip:
            return SurfacePresentation(
                geometry: ParametricGeometry.mobiusStrip(context: defaultContext),
                scale: .init(repeating: 1.85),
                position: [0.0, 0.6, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .helicoid:
            return SurfacePresentation(
                geometry: ParametricGeometry.helicoid(context: defaultContext, radius: 1.6, pitch: 0.12, turns: 3.5),
                scale: .init(repeating: 0.82),
                position: [0.0, 0.25, 0.0],
                orientation: simd_quatf(angle: 0.0, axis: Satin.worldUpDirection)
            )
        case .superellipsoid:
            return SurfacePresentation(
                geometry: ParametricGeometry.superellipsoid(
                    context: defaultContext,
                    radius: [1.0, 0.85, 1.2],
                    exponentV: 0.35,
                    exponentU: 0.3
                ),
                scale: .init(repeating: 1.55),
                position: [0.0, 0.5, 0.0],
                orientation: simd_quatf(angle: .pi * 0.08, axis: Satin.worldRightDirection)
            )
        case .kleinBottle:
            return SurfacePresentation(
                geometry: ParametricGeometry.kleinBottle(context: defaultContext),
                scale: .init(repeating: 0.7),
                position: [0.0, 0.85, 0.0],
                orientation: simd_quatf(angle: .pi * 0.45, axis: Satin.worldRightDirection)
            )
        case .catenoid:
            return SurfacePresentation(
                geometry: ParametricGeometry.catenoid(context: defaultContext, radius: 0.42, height: 2.6),
                scale: .init(repeating: 1.35),
                position: [0.0, 0.2, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .paraboloid:
            return SurfacePresentation(
                geometry: ParametricGeometry.paraboloid(context: defaultContext, radiusX: 1.35, radiusY: 1.35, height: 2.2),
                scale: .init(repeating: 1.3),
                position: [0.0, -0.1, 0.0],
                orientation: simd_quatf(angle: -.pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .enneperSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.enneperSurface(context: defaultContext, scale: 0.38, extent: 2.15),
                scale: .init(repeating: 1.0),
                position: [0.0, 0.3, 0.0],
                orientation: simd_quatf(angle: -.pi * 0.15, axis: Satin.worldRightDirection)
            )
        case .pseudosphere:
            return SurfacePresentation(
                geometry: ParametricGeometry.pseudosphere(context: defaultContext, radius: 1.0, heightExtent: 2.9),
                scale: .init(repeating: 1.45),
                position: [0.0, 0.15, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .dupinCyclide:
            return SurfacePresentation(
                geometry: ParametricGeometry.dupinCyclide(
                    context: defaultContext,
                    majorRadius: 1.4,
                    minorRadius: 0.48,
                    torusOffset: 2.2,
                    inversionRadius: 2.6
                ),
                scale: .init(repeating: 1.0),
                position: [0.0, 0.55, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .romanSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.romanSurface(context: defaultContext, scale: 2.2),
                scale: .init(repeating: 1.15),
                position: [0.0, 0.3, 0.0],
                orientation: simd_quatf(angle: .pi * 0.12, axis: Satin.worldRightDirection)
            )
        case .crossCap:
            return SurfacePresentation(
                geometry: ParametricGeometry.crossCap(context: defaultContext, scale: 2.6),
                scale: .init(repeating: 0.95),
                position: [0.0, 0.45, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .bourSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.bourSurface(context: defaultContext, radius: 1.25, turns: 4.0, scale: 0.72),
                scale: .init(repeating: 1.2),
                position: [0.0, 0.3, 0.0],
                orientation: simd_quatf(angle: .pi * 0.18, axis: Satin.worldRightDirection)
            )
        case .breatherSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.breatherSurface(
                    context: defaultContext,
                    parameterA: 0.42,
                    rangeU: -12.0 ... 12.0,
                    rangeV: -24.0 ... 24.0,
                    scale: 0.24
                ),
                scale: .init(repeating: 1.0),
                position: [0.0, 0.35, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .diniSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.diniSurface(
                    context: defaultContext,
                    radius: 1.0,
                    twist: 0.18,
                    rangeU: 0.0 ... (.pi * 5.0),
                    rangeV: 0.12 ... 1.35
                ),
                scale: .init(repeating: 1.3),
                position: [0.0, 0.1, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        }
    }

    func applySurface(named title: String) {
        let option = SurfaceOption.from(title: title)
        let presentation = makePresentation(for: option)
        mesh.geometry = presentation.geometry
        mesh.scale = presentation.scale
        mesh.position = presentation.position
        baseOrientation = presentation.orientation
    }

    override func update() {
        cameraController.update()

        let theta = Float(getTime() - startTime)
        let spin = simd_quatf(angle: theta * 0.32, axis: Satin.worldUpDirection)
        let tilt = simd_quatf(angle: sin(theta * 0.45) * 0.18, axis: simd_normalize([0.6, 0.0, 0.8]))
        mesh.orientation = spin * tilt * baseOrientation
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
