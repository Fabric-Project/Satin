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

    override var paramKeys: [String] { ["Surface", "Shape"] }
    override var params: [String: ParameterGroup?] {
        [
            "Surface": surfaceParams,
            "Shape": shapeParams
        ]
    }

    private let surfaceParam = StringParameter(
        "Surface",
        SurfaceOption.mobiusStrip.rawValue,
        SurfaceOption.allCases.map(\.rawValue),
        .dropdown
    )
    private let uResolutionParam = IntParameter("U Resolution", 192, 24, 320, .slider)
    private let vResolutionParam = IntParameter("V Resolution", 96, 8, 224, .slider)

    private lazy var surfaceParams = ParameterGroup("Surface", [
        surfaceParam,
        uResolutionParam,
        vResolutionParam
    ])

    private var shapeParams = ParameterGroup("Shape")
    private var surfaceSubscriptions: [AnyCancellable] = []
    private var shapeSubscriptions: [AnyCancellable] = []
    private var baseOrientation = simd_quatf(angle: 0.0, axis: Satin.worldUpDirection)

    lazy var surfaceMaterial: Material = {
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
        geometry: ParametricGeometry.mobiusStrip(context: defaultContext),
        material: surfaceMaterial
    )

    lazy var light0 = DirectionalLight(context: defaultContext, color: [1.0, 0.97, 0.94], intensity: 1.0)
    lazy var light1 = DirectionalLight(context: defaultContext, color: [0.72, 0.82, 1.0], intensity: 0.45)

    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [light0, light1, cycloramaMesh, mesh])
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 1.25, 7.5], near: 0.01, far: 200.0, fov: 32.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)
    lazy var startTime = getTime()

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

        configureShapeParameters(for: currentSurface, rebuildInspector: false)
        setupParameterSubscriptions()

        loadHdri()
        rebuildGeometry()
        camera.lookAt(target: [0.0, 0.4, 0.0])

#if os(visionOS)
        metalView.backgroundColor = .clear
#endif

        super.setup()
    }

    private var currentSurface: SurfaceOption {
        SurfaceOption.from(title: surfaceParam.value)
    }

    private var surfaceResolution: simd_int2 {
        [Int32(uResolutionParam.value), Int32(vResolutionParam.value)]
    }

    private func setupParameterSubscriptions() {
        surfaceSubscriptions = [
            surfaceParam.valuePublisher.sink { [weak self] value in
                guard let self = self else { return }
                self.configureShapeParameters(for: SurfaceOption.from(title: value), rebuildInspector: true)
                self.rebuildGeometry()
            },
            uResolutionParam.valuePublisher.sink { [weak self] _ in
                self?.rebuildGeometry()
            },
            vResolutionParam.valuePublisher.sink { [weak self] _ in
                self?.rebuildGeometry()
            }
        ]

        resubscribeShapeParameters()
    }

    private func resubscribeShapeParameters() {
        shapeSubscriptions.forEach { $0.cancel() }
        shapeSubscriptions = shapeParams.params.compactMap(makeGeometrySubscription(for:))
    }

    private func makeGeometrySubscription(for param: any Parameter) -> AnyCancellable? {
        if let param = param as? FloatParameter {
            return param.valuePublisher.sink { [weak self] _ in
                self?.rebuildGeometry()
            }
        }

        if let param = param as? IntParameter {
            return param.valuePublisher.sink { [weak self] _ in
                self?.rebuildGeometry()
            }
        }

        if let param = param as? StringParameter {
            return param.valuePublisher.sink { [weak self] _ in
                self?.rebuildGeometry()
            }
        }

        return nil
    }

    private func configureShapeParameters(for option: SurfaceOption, rebuildInspector: Bool) {
        shapeParams = makeShapeParameters(for: option)
        resubscribeShapeParameters()

        if rebuildInspector {
            setupInspector()
        }
    }

    private func makeShapeParameters(for option: SurfaceOption) -> ParameterGroup {
        switch option {
        case .mobiusStrip:
            return ParameterGroup("Shape", [
                FloatParameter("Radius", 1.0, 0.2, 2.5, .slider),
                FloatParameter("Width", 0.35, 0.05, 1.0, .slider)
            ])
        case .helicoid:
            return ParameterGroup("Shape", [
                FloatParameter("Radius", 1.6, 0.25, 3.0, .slider),
                FloatParameter("Pitch", 0.12, 0.02, 0.5, .slider),
                FloatParameter("Turns", 3.5, 1.0, 8.0, .slider)
            ])
        case .superellipsoid:
            return ParameterGroup("Shape", [
                FloatParameter("Radius X", 1.0, 0.2, 2.0, .slider),
                FloatParameter("Radius Y", 0.85, 0.2, 2.0, .slider),
                FloatParameter("Radius Z", 1.2, 0.2, 2.0, .slider),
                FloatParameter("Exponent U", 0.3, 0.1, 2.5, .slider),
                FloatParameter("Exponent V", 0.35, 0.1, 2.5, .slider)
            ])
        case .kleinBottle:
            return ParameterGroup("Shape", [
                FloatParameter("Radius", 2.0, 0.5, 3.5, .slider),
                FloatParameter("Tube", 0.55, 0.1, 1.25, .slider)
            ])
        case .catenoid:
            return ParameterGroup("Shape", [
                FloatParameter("Radius", 0.42, 0.1, 1.2, .slider),
                FloatParameter("Height", 2.6, 0.5, 5.0, .slider)
            ])
        case .paraboloid:
            return ParameterGroup("Shape", [
                FloatParameter("Radius X", 1.35, 0.2, 3.0, .slider),
                FloatParameter("Radius Y", 1.35, 0.2, 3.0, .slider),
                FloatParameter("Height", 2.2, 0.2, 5.0, .slider)
            ])
        case .enneperSurface:
            return ParameterGroup("Shape", [
                FloatParameter("Scale", 0.38, 0.05, 1.2, .slider),
                FloatParameter("Extent", 2.15, 0.5, 4.0, .slider)
            ])
        case .pseudosphere:
            return ParameterGroup("Shape", [
                FloatParameter("Radius", 1.0, 0.2, 2.0, .slider),
                FloatParameter("Extent", 2.9, 0.5, 6.0, .slider)
            ])
        case .dupinCyclide:
            return ParameterGroup("Shape", [
                FloatParameter("Major Radius", 1.4, 0.3, 3.0, .slider),
                FloatParameter("Minor Radius", 0.48, 0.05, 1.5, .slider),
                FloatParameter("Offset", 2.2, 0.4, 4.0, .slider),
                FloatParameter("Inversion", 2.6, 0.5, 5.0, .slider)
            ])
        case .romanSurface:
            return ParameterGroup("Shape", [
                FloatParameter("Scale", 2.2, 0.3, 4.0, .slider)
            ])
        case .crossCap:
            return ParameterGroup("Shape", [
                FloatParameter("Scale", 2.6, 0.3, 4.0, .slider)
            ])
        case .bourSurface:
            return ParameterGroup("Shape", [
                FloatParameter("Radius", 1.25, 0.2, 2.5, .slider),
                FloatParameter("Turns", 4.0, 1.0, 8.0, .slider),
                FloatParameter("Scale", 0.72, 0.1, 1.5, .slider)
            ])
        case .breatherSurface:
            return ParameterGroup("Shape", [
                FloatParameter("Parameter A", 0.42, 0.08, 0.9, .slider),
                FloatParameter("Scale", 0.24, 0.05, 0.8, .slider),
                FloatParameter("U Extent", 12.0, 2.0, 20.0, .slider),
                FloatParameter("V Extent", 24.0, 4.0, 40.0, .slider)
            ])
        case .diniSurface:
            return ParameterGroup("Shape", [
                FloatParameter("Radius", 1.0, 0.2, 2.0, .slider),
                FloatParameter("Twist", 0.18, 0.02, 0.5, .slider),
                FloatParameter("Turns", 5.0, 1.0, 8.0, .slider),
                FloatParameter("V Min", 0.12, 0.02, 1.0, .slider),
                FloatParameter("V Max", 1.35, 0.2, 2.8, .slider)
            ])
        }
    }

    private func rebuildGeometry() {
        let presentation = makePresentation(for: currentSurface)
        mesh.geometry = presentation.geometry
        mesh.scale = presentation.scale
        mesh.position = presentation.position
        baseOrientation = presentation.orientation
    }

    private func makePresentation(for option: SurfaceOption) -> SurfacePresentation {
        let resolution = surfaceResolution

        switch option {
        case .mobiusStrip:
            let radius = floatValue("Radius", default: 1.0)
            let width = floatValue("Width", default: 0.35)
            return SurfacePresentation(
                geometry: ParametricGeometry.mobiusStrip(context: defaultContext, radius: radius, width: width, resolution: resolution),
                scale: .init(repeating: 1.85),
                position: [0.0, 0.6, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .helicoid:
            let radius = floatValue("Radius", default: 1.6)
            let pitch = floatValue("Pitch", default: 0.12)
            let turns = floatValue("Turns", default: 3.5)
            return SurfacePresentation(
                geometry: ParametricGeometry.helicoid(context: defaultContext, radius: radius, pitch: pitch, turns: turns, resolution: resolution),
                scale: .init(repeating: 0.82),
                position: [0.0, 0.25, 0.0],
                orientation: simd_quatf(angle: 0.0, axis: Satin.worldUpDirection)
            )
        case .superellipsoid:
            return SurfacePresentation(
                geometry: ParametricGeometry.superellipsoid(
                    context: defaultContext,
                    radius: [
                        floatValue("Radius X", default: 1.0),
                        floatValue("Radius Y", default: 0.85),
                        floatValue("Radius Z", default: 1.2)
                    ],
                    exponentV: floatValue("Exponent V", default: 0.35),
                    exponentU: floatValue("Exponent U", default: 0.3),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.55),
                position: [0.0, 0.5, 0.0],
                orientation: simd_quatf(angle: .pi * 0.08, axis: Satin.worldRightDirection)
            )
        case .kleinBottle:
            return SurfacePresentation(
                geometry: ParametricGeometry.kleinBottle(
                    context: defaultContext,
                    radius: floatValue("Radius", default: 2.0),
                    tube: floatValue("Tube", default: 0.55),
                    resolution: resolution
                ),
                scale: .init(repeating: 0.7),
                position: [0.0, 0.85, 0.0],
                orientation: simd_quatf(angle: .pi * 0.45, axis: Satin.worldRightDirection)
            )
        case .catenoid:
            return SurfacePresentation(
                geometry: ParametricGeometry.catenoid(
                    context: defaultContext,
                    radius: floatValue("Radius", default: 0.42),
                    height: floatValue("Height", default: 2.6),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.35),
                position: [0.0, 0.2, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .paraboloid:
            return SurfacePresentation(
                geometry: ParametricGeometry.paraboloid(
                    context: defaultContext,
                    radiusX: floatValue("Radius X", default: 1.35),
                    radiusY: floatValue("Radius Y", default: 1.35),
                    height: floatValue("Height", default: 2.2),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.3),
                position: [0.0, -0.1, 0.0],
                orientation: simd_quatf(angle: -.pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .enneperSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.enneperSurface(
                    context: defaultContext,
                    scale: floatValue("Scale", default: 0.38),
                    extent: floatValue("Extent", default: 2.15),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.0),
                position: [0.0, 0.3, 0.0],
                orientation: simd_quatf(angle: -.pi * 0.15, axis: Satin.worldRightDirection)
            )
        case .pseudosphere:
            return SurfacePresentation(
                geometry: ParametricGeometry.pseudosphere(
                    context: defaultContext,
                    radius: floatValue("Radius", default: 1.0),
                    heightExtent: floatValue("Extent", default: 2.9),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.45),
                position: [0.0, 0.15, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .dupinCyclide:
            return SurfacePresentation(
                geometry: ParametricGeometry.dupinCyclide(
                    context: defaultContext,
                    majorRadius: floatValue("Major Radius", default: 1.4),
                    minorRadius: floatValue("Minor Radius", default: 0.48),
                    torusOffset: floatValue("Offset", default: 2.2),
                    inversionRadius: floatValue("Inversion", default: 2.6),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.0),
                position: [0.0, 0.55, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .romanSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.romanSurface(
                    context: defaultContext,
                    scale: floatValue("Scale", default: 2.2),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.15),
                position: [0.0, 0.3, 0.0],
                orientation: simd_quatf(angle: .pi * 0.12, axis: Satin.worldRightDirection)
            )
        case .crossCap:
            return SurfacePresentation(
                geometry: ParametricGeometry.crossCap(
                    context: defaultContext,
                    scale: floatValue("Scale", default: 2.6),
                    resolution: resolution
                ),
                scale: .init(repeating: 0.95),
                position: [0.0, 0.45, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .bourSurface:
            return SurfacePresentation(
                geometry: ParametricGeometry.bourSurface(
                    context: defaultContext,
                    radius: floatValue("Radius", default: 1.25),
                    turns: floatValue("Turns", default: 4.0),
                    scale: floatValue("Scale", default: 0.72),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.2),
                position: [0.0, 0.3, 0.0],
                orientation: simd_quatf(angle: .pi * 0.18, axis: Satin.worldRightDirection)
            )
        case .breatherSurface:
            let uExtent = floatValue("U Extent", default: 12.0)
            let vExtent = floatValue("V Extent", default: 24.0)
            return SurfacePresentation(
                geometry: ParametricGeometry.breatherSurface(
                    context: defaultContext,
                    parameterA: floatValue("Parameter A", default: 0.42),
                    rangeU: -uExtent ... uExtent,
                    rangeV: -vExtent ... vExtent,
                    scale: floatValue("Scale", default: 0.24),
                    resolution: resolution
                ),
                scale: .init(repeating: 1.0),
                position: [0.0, 0.35, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        case .diniSurface:
            let turns = floatValue("Turns", default: 5.0)
            let vMin = floatValue("V Min", default: 0.12)
            let vMax = max(floatValue("V Max", default: 1.35), vMin + 0.05)
            return SurfacePresentation(
                geometry: ParametricGeometry.diniSurface(
                    context: defaultContext,
                    radius: floatValue("Radius", default: 1.0),
                    twist: floatValue("Twist", default: 0.18),
                    rangeU: 0.0 ... (.pi * turns),
                    rangeV: vMin ... vMax,
                    resolution: resolution
                ),
                scale: .init(repeating: 1.3),
                position: [0.0, 0.1, 0.0],
                orientation: simd_quatf(angle: .pi * 0.5, axis: Satin.worldRightDirection)
            )
        }
    }

    private func floatValue(_ label: String, default value: Float) -> Float {
        shapeParams.get(label, as: FloatParameter.self)?.value ?? value
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

    private func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
            scene.environmentIntensity = 0.05
        }
    }
}
