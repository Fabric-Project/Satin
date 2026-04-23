import Metal
import MetalKit
import Satin

final class SSGIProjectorRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }
    override var colorPixelFormat: MTLPixelFormat { .rgba16Float }
    override var depthPixelFormat: MTLPixelFormat { .depth32Float }

    override var paramKeys: [String] { ["App", "SSGI", "SSGI Blur", "SSGI Composite"] }
    override var params: [String: ParameterGroup?] {
        [
            "App": appParams,
            "SSGI": ssgiPostProcessor.ssgiMaterial.parameters,
            "SSGI Blur": ssgiPostProcessor.blurMaterial.parameters,
            "SSGI Composite": ssgiPostProcessor.compositeMaterial.parameters
        ]
    }

    private lazy var appParams = ParameterGroup("App", [
        FloatParameter("SSGI Resolution", 0.5, 0.25, 1.0, .slider, "Internal SSGI resolution relative to the main scene."),
        FloatParameter("Projector Intensity", 180.0, 10.0, 320.0, .slider, "Brightness of the moving projector light."),
        FloatParameter("Environment Intensity", 0.025, 0.0, 0.15, .slider, "IBL contribution mixed with the projector."),
        FloatParameter("Projector Motion", 1.0, 0.0, 2.0, .slider, "Speed multiplier for the projector sweep."),
        FloatParameter("Object Motion", 1.0, 0.0, 2.0, .slider, "Speed multiplier for the animated hero objects.")
    ])

    private lazy var lightHelperGeo = IcoSphereGeometry(context: defaultContext, radius: 0.16, resolution: 1)
    private lazy var lightHelperMat = BasicColorMaterial(context: defaultContext, color: [1.0, 0.98, 0.9, 1.0], blending: .disabled)
    private lazy var lightHelperMesh = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat)

    private lazy var floorMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, size: 11.0, orientation: .zx),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.92, 0.94, 0.98, 1.0],
            metallic: 0.0,
            roughness: 0.98
        )
    )

    private lazy var backdropMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: 11.0, height: 6.5, orientation: .xy),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.9, 0.92, 0.96, 1.0],
            metallic: 0.0,
            roughness: 0.99
        )
    )

    private lazy var baseMesh = Mesh(
        context: defaultContext,
        geometry: BoxGeometry(context: defaultContext, width: 1.75, height: 0.22, depth: 1.75, resolution: 4),
        material: StandardMaterial(context: defaultContext, baseColor: [0.95, 0.95, 0.97, 1.0], metallic: 0.12, roughness: 0.84)
    )

    private lazy var torusMesh = Mesh(
        context: defaultContext,
        geometry: TorusGeometry(context: defaultContext, minorRadius: 0.12, majorRadius: 0.62),
        material: StandardMaterial(context: defaultContext, baseColor: [0.99, 0.99, 1.0, 1.0], metallic: 0.95, roughness: 0.2, specular: 1.0)
    )

    private lazy var sphereMesh = Mesh(
        context: defaultContext,
        geometry: IcoSphereGeometry(context: defaultContext, radius: 0.55, resolution: 4),
        material: StandardMaterial(context: defaultContext, baseColor: [0.96, 0.82, 0.7, 1.0], metallic: 0.18, roughness: 0.32, specular: 0.85)
    )

    private lazy var boxMesh = Mesh(
        context: defaultContext,
        geometry: BoxGeometry(context: defaultContext, width: 1.0, height: 1.8, depth: 1.0, resolution: 3),
        material: StandardMaterial(context: defaultContext, baseColor: [0.72, 0.84, 0.98, 1.0], metallic: 0.08, roughness: 0.52, specular: 0.7)
    )

    private lazy var coneMesh = Mesh(
        context: defaultContext,
        geometry: ConeGeometry(context: defaultContext, radius: 0.54, height: 1.6, angularResolution: 72, radialResolution: 1, verticalResolution: 8),
        material: StandardMaterial(context: defaultContext, baseColor: [0.93, 0.89, 0.83, 1.0], metallic: 0.12, roughness: 0.56, specular: 0.7)
    )

    private lazy var cylinderMesh = Mesh(
        context: defaultContext,
        geometry: CylinderGeometry(context: defaultContext, radius: 0.4, height: 1.55, angularResolution: 72, radialResolution: 1, verticalResolution: 5),
        material: StandardMaterial(context: defaultContext, baseColor: [0.86, 0.88, 0.92, 1.0], metallic: 0.4, roughness: 0.36, specular: 0.84)
    )

    private lazy var projectorLight = SpotLight(
        context: defaultContext,
        color: [1.0, 1.0, 1.0],
        intensity: 180.0,
        radius: 14.0,
        angleInner: 14.0,
        angleOuter: 23.0
    )

    private lazy var scene = IBLScene(
        context: defaultContext,
        label: "SSGI Projector Scene",
        [projectorLight, floorMesh, backdropMesh, baseMesh, torusMesh, sphereMesh, boxMesh, coneMesh, cylinderMesh]
    )

    private lazy var camera = PerspectiveCamera(context: defaultContext, position: [7.4, 4.6, 8.6], near: 0.01, far: 500.0, fov: 32.0)
    private lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    private lazy var sceneRenderer: Renderer = {
        let renderer = Renderer(
            label: "SSGI Projector Scene Renderer",
            context: defaultContext,
            colorLoadAction: .clear,
            colorStoreAction: .store,
            depthLoadAction: .clear,
            depthStoreAction: .store,
            frameBufferOnly: false
        )
        renderer.renderingMode = .deferredGeometry
        renderer.activeOutputs = [.color, .albedo, .normals, .pbr]
        renderer.colorTextureStorageMode = .private
        renderer.depthTextureStorageMode = .private
        return renderer
    }()

    private lazy var ssgiPostProcessor = SsgiPostProcessor(context: defaultContext)
    private lazy var compositorMaterial = BasicTextureMaterial(context: defaultContext)
    private lazy var compositor = PostProcessor(
        label: "SSGI Projector Compositor",
        context: defaultContext,
        material: compositorMaterial,
        depthLoadAction: .dontCare,
        depthStoreAction: .dontCare
    )

    private lazy var textureLoader = MTKTextureLoader(device: device)
    private lazy var startTime = getTime()

    override func setup() {
        loadHdri()
        loadProjectorTexture()
        sceneRenderer.clearColor = .init(red: 0.07, green: 0.075, blue: 0.09, alpha: 1.0)

        setupProjector()
        setupScene()

        camera.lookAt(target: [0.0, -0.2, -1.0])

        super.setup()
    }

    override func update() {
        cameraController.update()

        let projectorMotion = appParams.get("Projector Motion", as: FloatParameter.self)?.value ?? 1.0
        let objectMotion = appParams.get("Object Motion", as: FloatParameter.self)?.value ?? 1.0
        let time = Float(getTime() - startTime)
        let projectorTheta = time * 0.48 * projectorMotion
        let objectTheta = time * 0.48 * objectMotion

        torusMesh.orientation = simd_quatf(angle: objectTheta * 1.35, axis: Satin.worldUpDirection)
        torusMesh.orientation *= simd_quatf(angle: objectTheta * 0.42, axis: Satin.worldRightDirection)

        sphereMesh.position.y = -0.45 + sin(objectTheta * 1.2) * 0.18
        boxMesh.orientation = simd_quatf(angle: -objectTheta * 0.18, axis: Satin.worldUpDirection)
        coneMesh.orientation = simd_quatf(angle: objectTheta * 0.26, axis: Satin.worldUpDirection)
        cylinderMesh.orientation = simd_quatf(angle: -objectTheta * 0.2, axis: Satin.worldUpDirection)

        projectorLight.intensity = appParams.get("Projector Intensity", as: FloatParameter.self)?.value ?? 180.0
        scene.environmentIntensity = appParams.get("Environment Intensity", as: FloatParameter.self)?.value ?? 0.025
        ssgiPostProcessor.resolutionScale = appParams.get("SSGI Resolution", as: FloatParameter.self)?.value ?? 0.5

        projectorLight.position = simd_make_float3(
            sin(projectorTheta) * 1.85,
            3.85 + sin(projectorTheta * 0.62) * 0.14,
            4.75 + cos(projectorTheta * 0.74) * 0.28
        )

        let target = simd_make_float3(
            sin(projectorTheta * 0.54) * 0.35,
            -0.14 + sin(projectorTheta * 0.38) * 0.05,
            -1.3 + cos(projectorTheta * 0.46) * 0.24
        )
        projectorLight.lookAt(target: target, up: Satin.worldUpDirection)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        sceneRenderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        ssgiPostProcessor.colorTexture = sceneRenderer.colorTexture
        ssgiPostProcessor.depthTexture = sceneRenderer.depthTexture
        ssgiPostProcessor.normalTexture = sceneRenderer.normalTexture
        ssgiPostProcessor.albedoTexture = sceneRenderer.albedoTexture
        ssgiPostProcessor.pbrTexture = sceneRenderer.pbrTexture
        ssgiPostProcessor.sceneCamera = camera
        ssgiPostProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)

        compositorMaterial.texture = ssgiPostProcessor.outputTexture ?? sceneRenderer.colorTexture
        compositor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / max(size.height, 1.0)
        sceneRenderer.resize(size)
        ssgiPostProcessor.resize(size: size, scaleFactor: scaleFactor)
        compositor.resize(size: size, scaleFactor: scaleFactor)
    }

    private func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
            scene.environmentIntensity = appParams.get("Environment Intensity", as: FloatParameter.self)?.value ?? 0.025
        }
    }

    private func loadProjectorTexture() {
        let url = texturesURL.appendingPathComponent("PM5544_with_non-PAL_signals.png")
        do {
            projectorLight.projectionTexture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: true,
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically,
            ])
        } catch {
            print(error.localizedDescription)
        }
    }

    private func setupProjector() {
        projectorLight.label = "Projector"
        projectorLight.position = [0.0, 3.85, 4.75]
        projectorLight.castShadow = true
        projectorLight.projectionMode = .color
        projectorLight.shadow.resolution = (1024, 1024)
        projectorLight.shadow.bias = 0.0001
        projectorLight.shadow.radius = 1
        projectorLight.shadow.strength = 2
        projectorLight.add(lightHelperMesh)
        projectorLight.lookAt(target: [0.0, -0.15, -1.3], up: Satin.worldUpDirection)
    }

    private func setupScene() {
        floorMesh.label = "Floor"
        floorMesh.position.y = -1.0
        floorMesh.receiveShadow = true

        backdropMesh.label = "Backdrop"
        backdropMesh.position = [0.0, 2.1, -4.8]
        backdropMesh.receiveShadow = true

        baseMesh.label = "Base"
        baseMesh.position = [-0.2, -0.89, -0.95]
        baseMesh.castShadow = true
        baseMesh.receiveShadow = true

        torusMesh.label = "Main"
        torusMesh.position = [-0.2, 0.08, -0.95]
        torusMesh.castShadow = true
        torusMesh.receiveShadow = true

        sphereMesh.label = "Sphere"
        sphereMesh.position = [1.7, -0.45, 0.55]
        sphereMesh.castShadow = true
        sphereMesh.receiveShadow = true

        boxMesh.label = "Box"
        boxMesh.position = [-1.95, -0.1, 0.75]
        boxMesh.castShadow = true
        boxMesh.receiveShadow = true

        coneMesh.label = "Cone"
        coneMesh.position = [1.35, -0.2, -2.1]
        coneMesh.castShadow = true
        coneMesh.receiveShadow = true

        cylinderMesh.label = "Cylinder"
        cylinderMesh.position = [-2.45, -0.22, -1.85]
        cylinderMesh.castShadow = true
        cylinderMesh.receiveShadow = true
    }
}
