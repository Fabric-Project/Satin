//
//  ARPBRRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/25/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Metal
import MetalKit
import MetalPerformanceShaders

import Satin

fileprivate final class ARScene: Object, IBLEnvironment {
    private var assetsURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Assets") }
    private var sharedAssetsURL: URL { assetsURL.appendingPathComponent("Shared") }
    private var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    var environmentIntensity: Float = 1.0

    var environment: MTLTexture?
    var cubemapTexture: MTLTexture?

    var irradianceTexture: MTLTexture?
    var irradianceTexcoordTransform: simd_float3x3 = matrix_identity_float3x3

    var reflectionTexture: MTLTexture?
    var reflectionTexcoordTransform: simd_float3x3 = matrix_identity_float3x3

    var brdfTexture: MTLTexture?

    unowned var session: ARSession

    public init(label: String, _ children: [Object] = [], session: ARSession) {
        self.session = session
        super.init(label: label, children)
        Task(priority: .background) {
            if let device = MTLCreateSystemDefaultDevice() {
                self.generateBRDFLUT(device: device)
            }
        }
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    func generateBRDFLUT(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let _brdfTexture = BrdfGenerator(device: device, size: 512).encode(commandBuffer: commandBuffer)

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.brdfTexture = _brdfTexture
        }
        commandBuffer.commit()
    }

    func getClosestProbe(_ probes: [AREnvironmentProbeAnchor], position: simd_float3) -> AREnvironmentProbeAnchor? {
        var closest: AREnvironmentProbeAnchor? = nil
        var closestDistance: Float = .infinity
        for probe in probes {
            let transform = probe.transform
            let probePosition = simd_make_float3(transform.columns.3)
            let dist = simd_length(probePosition - position)
            if dist < closestDistance {
                closestDistance = dist
                closest = probe
            }
        }
        return closest
    }

    override func encode(_ commandBuffer: MTLCommandBuffer) {
        guard let currentFrame = session.currentFrame else { return }

        if let lightEstimate = currentFrame.lightEstimate {
            environmentIntensity = Float(lightEstimate.ambientIntensity / 2000.0)
        }

        let probes = currentFrame.anchors.compactMap { $0 as? AREnvironmentProbeAnchor }
        if !probes.isEmpty {
            traverse { child in
                if let renderable = child as? Renderable, let material = renderable.material as? StandardMaterial {
                    if let probe = getClosestProbe(probes, position: child.worldPosition),
                       let texture = probe.environmentTexture, texture.textureType == .typeCube
                    {
                        material.setTexture(texture, type: .reflection)
                        material.setTexture(texture, type: .irradiance)

                        let transform = simd_float3x3(
                            simd_make_float3(probe.transform.columns.0),
                            simd_make_float3(probe.transform.columns.1),
                            simd_make_float3(probe.transform.columns.2)
                        ) * matrix_float3x3(simd_quatf(angle: Float.pi, axis: Satin.worldUpDirection))

                        reflectionTexcoordTransform = transform
                        irradianceTexcoordTransform = transform

                        material.setTexcoordTransform(reflectionTexcoordTransform, type: .reflection)
                        material.setTexcoordTransform(irradianceTexcoordTransform, type: .irradiance)
                    }
                }
            }
        }
    }
}

fileprivate final class ARObject: Object {
    var anchor: ARAnchor? {
        didSet {
            if let anchor = anchor {
                worldMatrix = anchor.transform
                visible = true
            }
        }
    }

    unowned var session: ARSession

    init(label: String, children: [Object] = [], session: ARSession) {
        self.session = session
        super.init(label: label, children)
        self.visible = false
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    override func encode(_ commandBuffer: MTLCommandBuffer) {
        if let anchor = anchor,
           let currentFrame = session.currentFrame,
           let index = currentFrame.anchors.firstIndex(of: anchor)
        {
            worldMatrix = currentFrame.anchors[index].transform
        }
        super.encode(commandBuffer)
    }
}

final class Model: Object {
    private var assetsURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Assets") }
    private var sharedAssetsURL: URL { assetsURL.appendingPathComponent("Shared") }
    private var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }
    private var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }

    var material = PhysicalMaterial()

    override init() {
        super.init(label: "Suzanne")
        Task(priority: .background) {
            self.setupModel()
            await self.setupTextures()
        }
    }

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    private func setupModel() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        // we do this to make sure we don't recompile the material multiple times
        let cubeDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .r32Float, size: 1, mipmapped: false)
        let cubeTexture = device.makeTexture(descriptor: cubeDesc)
        material.setTexture(cubeTexture, type: .reflection)
        material.setTexture(cubeTexture, type: .irradiance)

        // we do this to make sure we don't recompile the material multiple times
        let tmpDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        let tmpTexture = device.makeTexture(descriptor: tmpDesc)
        material.setTexture(tmpTexture, type: .brdf)
        material.setTexture(tmpTexture, type: .baseColor)
        material.setTexture(tmpTexture, type: .occlusion)
        material.setTexture(tmpTexture, type: .metallic)
        material.setTexture(tmpTexture, type: .normal)
        material.setTexture(tmpTexture, type: .roughness)

        if let model = loadAsset(url: modelsURL.appendingPathComponent("Suzanne").appendingPathComponent("Suzanne.obj")) {
            var mesh: Mesh?
            model.apply { obj in
                if let m = obj as? Mesh {
                    mesh = m
                }
            }
            if let mesh = mesh {
                mesh.material = material
                mesh.label = "Suzanne Mesh"
                mesh.scale = .init(repeating: 0.25)

                let meshBounds = mesh.localBounds
                mesh.position.y += meshBounds.size.y * 0.5 + 0.05
                add(mesh)
            }
        }
    }

    func setupTextures() async {
        Task {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            let baseURL = modelsURL.appendingPathComponent("Suzanne")
            let maps: [PBRTextureType: URL] = [
                .baseColor: baseURL.appendingPathComponent("albedo.png"),
                .occlusion: baseURL.appendingPathComponent("ao.png"),
                .metallic: baseURL.appendingPathComponent("metallic.png"),
                .normal: baseURL.appendingPathComponent("normal.png"),
                .roughness: baseURL.appendingPathComponent("roughness.png"),
            ]

            let types = maps.compactMap { $0.key }
            let urls = maps.compactMap { $0.value }

            let loader = MTKTextureLoader(device: device)
            do {
                let options: [MTKTextureLoader.Option: Any] = [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically,
                    MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
                ]
                let textures = try await loader.newTextures(URLs: urls, options: options)

                DispatchQueue.main.async {
                    for (index, texture) in textures.enumerated() {
                        texture.label = types[index].textureName
                        self.material.setTexture(texture, type: types[index])
                    }
                }
            } catch {
                print(error.localizedDescription)
            }
        }
    }
}

final class ARPBRRenderer: BaseRenderer, MaterialDelegate {
    class PostMaterial: SourceMaterial {
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

        public var grainTexture: MTLTexture? {
            didSet {
                set(grainTexture, index: FragmentTextureIndex.Custom3)
            }
        }

        public var backgroundTexture: MTLTexture? {
            didSet {
                set(backgroundTexture, index: FragmentTextureIndex.Custom0)
            }
        }

        public var contentTexture: MTLTexture? {
            didSet {
                set(contentTexture, index: FragmentTextureIndex.Custom1)
            }
        }

        public var depthMaskTexture: MTLTexture? {
            didSet {
                set(depthMaskTexture, index: FragmentTextureIndex.Custom2)
            }
        }
    }

    override var paramKeys: [String] {
        return ["Material"]
    }

    override var params: [String: ParameterGroup?] {
        return [
            "Material": model.material.parameters,
        ]
    }

    var session = ARSession()

    var shadowPlaneMesh = {
        let material = BasicTextureMaterial(texture: nil, flipped: false)
        material.depthBias = DepthBias(bias: 100.0, slope: 100.0, clamp: 100.0)
        let mesh = Mesh(geometry: PlaneGeometry(size: 1.0, orientation: .zx), material: material)
        mesh.label = "Shadow Catcher"
        return mesh
    }()

    fileprivate lazy var modelContainer = ARObject(
        label: "Model Container",
        children: [shadowPlaneMesh, model],
        session: session
    )

    var model = Model()

    lazy var shadowRenderer = ObjectShadowRenderer(
        context: context,
        object: model,
        container: modelContainer,
        scene: scene,
        catcher: shadowPlaneMesh,
        blurRadius: 8.0,
        near: 0.01,
        far: 1.0,
        color: [0.0, 0.0, 0.0, 0.9]
    )

    fileprivate lazy var scene = ARScene(label: "Scene", [modelContainer], session: session)
    lazy var context = Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat, depthPixelFormat: .depth32Float)
    lazy var camera = ARPerspectiveCamera(session: session, metalView: metalView, near: 0.01, far: 100.0)
    lazy var renderer = Renderer(context: context, frameBufferOnly: false)

    var backgroundRenderer: ARBackgroundDepthRenderer!
    var featheredDepthMaskGenerator: ARFeatheredDepthMaskGenerator!

    lazy var postMaterial: PostMaterial = {
        let material = PostMaterial(pipelinesURL: pipelinesURL)
        material.depthWriteEnabled = false
        material.blending = .alpha
        return material
    }()

    lazy var postProcessor = PostProcessor(
        label: "Post Processor",
        context: Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat),
        material: postMaterial
    )

    lazy var startTime = getTime()

    override var depthPixelFormat: MTLPixelFormat { .invalid }

    override init() {
        super.init()

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .manual
        config.wantsHDREnvironmentTextures = true
        config.planeDetection = [.horizontal]
        config.frameSemantics = [.sceneDepth]
        config.sceneReconstruction = .mesh
        session.run(config)
    }

    override func setup() {
        metalView.preferredFramesPerSecond = 60

        model.material.delegate = self

        renderer.setClearColor(.zero)
        renderer.depthStoreAction = .store

        backgroundRenderer = ARBackgroundDepthRenderer(
            context: context,
            session: session,
            sessionPublisher: ARSessionPublisher(session: session),
            metalView: metalView,
            near: camera.near,
            far: camera.far,
            upscaleDepth: true,
            usePlaneDepth: false,
            useMeshDepth: false
        )

        featheredDepthMaskGenerator = ARFeatheredDepthMaskGenerator(
            device: device,
            pixelFormat: .r8Unorm,
            textureScale: 3,
            blurSigma: 4
        )
    }

    override func update() {
        let time = getTime() - startTime
        model.orientation = simd_quatf(angle: Float(time), axis: Satin.worldUpDirection)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        backgroundRenderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer
        )

        if modelContainer.visible {
            shadowRenderer.update(commandBuffer: commandBuffer)
        }

        renderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        // Compare depth

        var featheredDepthMaskTexture: MTLTexture?
        if let realDepthTexture = backgroundRenderer.depthTexture,
           let virtualDepthTexture = renderer.depthTexture
        {
            featheredDepthMaskTexture = featheredDepthMaskGenerator.encode(
                commandBuffer: commandBuffer,
                realDepthTexture: realDepthTexture,
                virtualDepthTexture: virtualDepthTexture
            )
        }

        // Post
        postMaterial.backgroundTexture = backgroundRenderer.colorTexture
        postMaterial.contentTexture = renderer.colorTexture
        postMaterial.depthMaskTexture = featheredDepthMaskTexture
        postMaterial.grainTexture = session.currentFrame?.cameraGrainTexture
        postMaterial.grainIntensity = session.currentFrame?.cameraGrainIntensity ?? 0
        postMaterial.time = Float(getTime() - startTime)

        postProcessor.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
        postProcessor.resize(size: size, scaleFactor: scaleFactor)
        featheredDepthMaskGenerator.resize(size)
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
            let anchor = AREnvironmentProbeAnchor(transform: result.worldTransform, extent: .init(repeating: 1.0))
            session.add(anchor: anchor)

            if let existingAnchor = modelContainer.anchor {
                session.remove(anchor: existingAnchor)
            }

            modelContainer.anchor = anchor
        }
    }

    private func normalizePoint(_ point: CGPoint, _ size: CGSize) -> simd_float2 {
#if os(macOS)
        return 2.0 * simd_make_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1.0
#else
        return 2.0 * simd_make_float2(Float(point.x / size.width), 1.0 - Float(point.y / size.height)) - 1.0
#endif
    }

    func updated(material: Material) {
        print("Material Updated: \(material.label)")
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
