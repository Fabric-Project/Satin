import Metal
import Satin

final class SSGICornellBoxRenderer: BaseRenderer {
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
        FloatParameter("SSGI Resolution", 1.0, 0.25, 1.0, .slider, "Internal SSGI resolution relative to the main scene."),
        FloatParameter("Light Intensity", 100.0, 10.0, 220.0, .slider, "Brightness of the Cornell box point light."),
        FloatParameter("Light Radius", 100.0, 10.0, 180.0, .slider, "Attenuation radius of the Cornell box point light."),
        FloatParameter("Light Height", 13.0, 10.0, 14.5, .slider, "Vertical position of the box light beneath the ceiling.")
    ])

    private lazy var redWallMaterial = StandardMaterial(
        context: defaultContext,
        baseColor: [1.0, 0.12, 0.12, 1.0],
        metallic: 0.0,
        roughness: 0.98,
        specular: 0.18
    )

    private lazy var greenWallMaterial = StandardMaterial(
        context: defaultContext,
        baseColor: [0.12, 1.0, 0.12, 1.0],
        metallic: 0.0,
        roughness: 0.98,
        specular: 0.18
    )

    private lazy var whiteWallMaterial = StandardMaterial(
        context: defaultContext,
        baseColor: [0.98, 0.98, 0.98, 1.0],
        metallic: 0.0,
        roughness: 0.98,
        specular: 0.18
    )

    private lazy var lightSourceMaterial = BasicColorMaterial(
        context: defaultContext,
        color: [1.0, 1.0, 1.0, 1.0],
        blending: .disabled
    )

    private let boxSize:Float = 18.0
    private let boxSizeHalf:Float = 9.0

    private lazy var leftWall = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: boxSize, height: boxSize, orientation: .yz),
        material: redWallMaterial
    )

    private lazy var rightWall = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: boxSize, height: boxSize, orientation: .zy),
        material: greenWallMaterial
    )

    private lazy var floorMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: boxSize, height: boxSize, orientation: .zx),
        material: whiteWallMaterial
    )

    private lazy var backWall = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: boxSize, height: boxSize, orientation: .xy),
        material: whiteWallMaterial
    )

    private lazy var ceilingMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: boxSize, height: boxSize, orientation: .xz),
        material: whiteWallMaterial
    )

    private lazy var tallBox = Mesh(
        context: defaultContext,
        geometry: BoxGeometry(context: defaultContext, width: 5.0, height: 7.0, depth: 5.0, resolution: 2),
        material: whiteWallMaterial
    )

    private lazy var shortBox = Mesh(
        context: defaultContext,
        geometry: BoxGeometry(context: defaultContext, width: 4.0, height: 4.0, depth: 4.0, resolution: 2),
        material: whiteWallMaterial
    )

    private lazy var lightSource = Mesh(
        context: defaultContext,
        geometry: CylinderGeometry(context: defaultContext, radius: 2.5, height: 0.5, angularResolution: 64, radialResolution: 1, verticalResolution: 1),
        material: lightSourceMaterial
    )

    private lazy var pointLight = PointLight(
        context: defaultContext,
        color: [1.0, 1.0, 1.0],
        intensity: 100.0,
        radius: 100.0
    )

    private lazy var scene = Object(
        context: defaultContext,
        label: "SSGI Cornell Box Scene",
        [pointLight, leftWall, rightWall, floorMesh, backWall, ceilingMesh, tallBox, shortBox, lightSource]
    )

    private lazy var camera = PerspectiveCamera(
        context: defaultContext,
        position: [0.0, 10.0, 30.0],
        near: 0.1,
        far: 100.0,
        fov: 40.0
    )

    private lazy var cameraController = OrbitPerspectiveCameraController(camera: camera, view: metalView)

    private lazy var sceneRenderer: Renderer = {
        let renderer = Renderer(
            label: "SSGI Cornell Box Scene Renderer",
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
        renderer.clearColor = .init(red: 0.67, green: 0.67, blue: 0.67, alpha: 1.0)
        return renderer
    }()

    private lazy var ssgiPostProcessor = SsgiPostProcessor(context: defaultContext)
    private lazy var compositorMaterial = BasicTextureMaterial(context: defaultContext)
    private lazy var compositor = PostProcessor(
        label: "SSGI Cornell Box Compositor",
        context: defaultContext,
        material: compositorMaterial,
        depthLoadAction: .dontCare,
        depthStoreAction: .dontCare
    )

    override func setup() {
        setupScene()

        ssgiPostProcessor.resolutionScale = 1.0
        ssgiPostProcessor.ssgiMaterial.radius = 12.0
        ssgiPostProcessor.ssgiMaterial.thickness = 1.0
        ssgiPostProcessor.ssgiMaterial.expFactor = 2.0
        ssgiPostProcessor.ssgiMaterial.jitterStrength = 1.0
        ssgiPostProcessor.ssgiMaterial.sliceCount = 4
        ssgiPostProcessor.ssgiMaterial.stepCount = 12
        ssgiPostProcessor.blurMaterial.radius = 4.0
        ssgiPostProcessor.blurMaterial.lumaPhi = 5.0
        ssgiPostProcessor.blurMaterial.depthPhi = 5.0
        ssgiPostProcessor.blurMaterial.normalPhi = 5.0
        ssgiPostProcessor.compositeMaterial.giIntensity = 10.0
        ssgiPostProcessor.compositeMaterial.aoIntensity = 1.0
        ssgiPostProcessor.compositeMaterial.aoLift = 0.0

        camera.lookAt(target: [0.0, 7.0, 0.0])
        cameraController.target.position = [0.0, 7.0, 0.0]
        cameraController.minimumZoomDistance = 8.0
        scene.attach(cameraController.target)

        super.setup()
    }

    override func update() {
        cameraController.update()

        ssgiPostProcessor.resolutionScale = appParams.get("SSGI Resolution", as: FloatParameter.self)?.value ?? 1.0

        let lightHeight = appParams.get("Light Height", as: FloatParameter.self)?.value ?? 13.0
        pointLight.intensity = appParams.get("Light Intensity", as: FloatParameter.self)?.value ?? 100.0
        pointLight.radius = appParams.get("Light Radius", as: FloatParameter.self)?.value ?? 100.0
        pointLight.position = [0.0, lightHeight, 0.0]

        lightSource.position = [0.0, min(lightHeight + 2.0, 14.92), 0.0]
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

    private func setupScene() {
        leftWall.label = "Left Wall"
        leftWall.position = [-boxSizeHalf, boxSizeHalf, 0.0]
        leftWall.receiveShadow = true

        rightWall.label = "Right Wall"
        rightWall.position = [boxSizeHalf, boxSizeHalf, 0.0]
        rightWall.receiveShadow = true

        floorMesh.label = "Floor"
        floorMesh.receiveShadow = true

        backWall.label = "Back Wall"
        backWall.position = [0.0, boxSizeHalf, -boxSizeHalf]
        backWall.receiveShadow = true

        ceilingMesh.label = "Ceiling"
        ceilingMesh.position = [0.0, boxSize, 0.0]
        ceilingMesh.receiveShadow = true

        tallBox.label = "Tall Box"
        tallBox.position = [-3.0, 3.5, -2.0]
        tallBox.orientation = simd_quatf(angle: .pi * 0.25, axis: Satin.worldUpDirection)
        tallBox.castShadow = true
        tallBox.receiveShadow = true

        shortBox.label = "Short Box"
        shortBox.position = [4.0, 2.0, 4.0]
        shortBox.orientation = simd_quatf(angle: -.pi * 0.1, axis: Satin.worldUpDirection)
        shortBox.castShadow = true
        shortBox.receiveShadow = true

        lightSource.label = "Emitter"
        lightSource.position = [0.0, 14.92, 0.0]
        lightSource.scale = [1.0, 1.0, 1.0]

        pointLight.label = "Point Light"
        pointLight.position = [0.0, 13.0, 0.0]
        pointLight.castShadow = true
        pointLight.shadow.resolution = (1024, 1024)
        pointLight.shadow.bias = 0.0002
        pointLight.shadow.normalBias = 0.02
        pointLight.shadow.radius = 1.0
        pointLight.shadow.strength = 1.0
    }
}
