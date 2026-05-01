//
//  PBRMRTRenderer.swift
//  Example
//
//  Created by OpenAI Codex on 4/22/26.
//

import Metal
import MetalKit
import Satin

final class PBRMRTRenderer: BaseRenderer {
    private enum PreviewOutput: CaseIterable {
        case color
        case depth
        case albedo
        case normals
        case pbr
        case velocity
        case emissive

        var title: String {
            switch self {
            case .color:
                return "Color"
            case .depth:
                return "Depth"
            case .albedo:
                return "Albedo"
            case .normals:
                return "Normals"
            case .pbr:
                return "PBR"
            case .velocity:
                return "Velocity"
            case .emissive:
                return "Emissive"
            }
        }
    }

    private struct OutputPreview {
        let output: PreviewOutput
//        let background: Mesh
        let mesh: Mesh
        let label: TextMesh?
    }

    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }
    override var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }

    override var colorPixelFormat: MTLPixelFormat {
        .rgba16Float
    }

    override var paramKeys: [String] {
        ["Material", "SSAO", "SSAO Blur", "SSAO Composite", "Motion Blur", "DOF"]
    }

    override var params: [String: ParameterGroup?] {
        [
            "Material": material.parameters,
            "SSAO": ssaoPostProcessor.ssaoMaterial.parameters,
            "SSAO Blur": ssaoPostProcessor.blurMaterial.parameters,
            "SSAO Composite": ssaoPostProcessor.compositeMaterial.parameters,
            "Motion Blur": motionBlurPostProcessor.motionBlurMaterial.parameters,
            "DOF": bokehDepthOfFieldPostProcessor.parameters
        ]
    }

    private let allOutputs: RendererOutputs = [.color, .albedo, .normals, .pbr, .velocity, .emissive]

    private var model: Object?
    private var outputPreviews: [OutputPreview] = []
    private var sceneBounds = Bounds()
    private lazy var textureLoader = MTKTextureLoader(device: device)

    private lazy var startTime = getTime()
    private lazy var sceneRenderer: Renderer = {
        let renderer = Renderer(
            label: "PBR MRT Scene Renderer",
            context: defaultContext,
            colorLoadAction: .clear,
            colorStoreAction: .store,
            depthLoadAction: .clear,
            depthStoreAction: .store,
            frameBufferOnly: false
        )
        renderer.renderingMode = .deferredGeometry
        renderer.activeOutputs = allOutputs
        renderer.colorTextureStorageMode = .private
        renderer.depthTextureStorageMode = .private
        return renderer
    }()

    private lazy var overlayContext = Context(
        device: device,
        sampleCount: sampleCount,
        colorPixelFormat: colorPixelFormat,
        depthPixelFormat: .invalid
    )

    private lazy var overlayRenderer: Renderer = {
        let renderer = Renderer(
            label: "PBR MRT Overlay Renderer",
            context: overlayContext,
            sortObjects: true,
            clearColor: [0, 0, 0, 0],
            colorLoadAction: .clear,
            colorStoreAction: .store,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
        return renderer
    }()

    private lazy var previewGeometry = QuadGeometry(context: overlayContext, size: 1.0)
    private lazy var previewStripMaterial = makeOverlayColorMaterial([0.035, 0.045, 0.06, 0.86])
    private lazy var previewTileMaterial = makeOverlayColorMaterial([0.07, 0.085, 0.11, 0.95])
    private lazy var ssaoPostProcessor = SsaoPostProcessor(context: defaultContext)
    private lazy var motionBlurPostProcessor = MotionBlurPostProcessor(context: defaultContext)
    private lazy var bokehDepthOfFieldPostProcessor = BokehDepthOfFieldPostProcessor(context: defaultContext)

    private lazy var overlayScene = Object(context: overlayContext, label: "MRT Overlay Scene")
    private lazy var overlayCamera = OrthographicCamera(
        context: overlayContext,
        left: 0.0,
        right: 1.0,
        bottom: 0.0,
        top: 1.0,
        near: 0.0,
        far: 20.0
    )

    private lazy var beautyMaterial: BasicTextureMaterial = {
        let material = BasicTextureMaterial(context: overlayContext)
        material.blending = .disabled
        material.depthWriteEnabled = false
        return material
    }()

    private lazy var beautyMesh: Mesh = {
        let mesh = Mesh(
            context: overlayContext,
            label: "Beauty",
            geometry: previewGeometry,
            material: beautyMaterial,
            renderOrder: 0
        )
        configureOverlay(mesh)
        return mesh
    }()

    private lazy var previewStripBackground: Mesh = {
        let mesh = Mesh(
            context: overlayContext,
            label: "MRT Strip Background",
            geometry: previewGeometry,
            material: previewStripMaterial,
            renderOrder: 10
        )
        configureOverlay(mesh)
        return mesh
    }()

    private lazy var overlayFontAtlas: FontAtlas? = try? FontAtlas.load(
        url: sharedAssetsURL.appendingPathComponent("Fonts/SFProRounded/SFProRoundedBold64.json")
    )

    private lazy var overlayFontTexture: MTLTexture? = {
        let loader = MTKTextureLoader(device: device)
        let url = sharedAssetsURL.appendingPathComponent("Fonts/SFProRounded/SFProRoundedBold64.png")
        let options: [MTKTextureLoader.Option: Any] = [
            MTKTextureLoader.Option.SRGB: false,
            MTKTextureLoader.Option.generateMipmaps: false
        ]
        return try? loader.newTexture(URL: url, options: options)
    }()

    private lazy var overlayLabelMaterial: TextMaterial? = {
        guard let fontTexture = overlayFontTexture else { return nil }
        let material = TextMaterial(context: overlayContext, color: [0.95, 0.97, 1.0, 1.0], fontTexture: fontTexture)
        material.depthWriteEnabled = false
        return material
    }()

    private lazy var skybox: Mesh = .init(
        context: defaultContext,
        label: "Skybox",
        geometry: SkyboxGeometry(context: defaultContext, size: 500),
        material: SkyboxMaterial(context: defaultContext)
    )
    
    private lazy var lightHolder = Object(context: defaultContext)
    

    private lazy var scene = IBLScene(context: defaultContext, label: "Scene", [skybox, lightHolder])
    private lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 0.0, 4.0], near: 0.01, far: 1000.0)
    private lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    private lazy var material = StandardMaterial(context: defaultContext)

    private var hasSceneBounds: Bool {
        sceneBounds.min.x.isFinite && sceneBounds.max.x.isFinite
    }

    override func setup() {
        loadHdri()
        setupTextures()
        setupSuzanneScene()
        setupLights()
        setupOverlayScene()

        scene.environmentIntensity = 0.375

#if os(visionOS)
        metalView.backgroundColor = .clear
        skybox.visible = false
#endif

        super.setup()
    }

    override func update() {
        
        let time = Float(getTime() - startTime)
        let theta = time * 0.2

//        model?.orientation = simd_quatf(angle: Float(getTime() - startTime) * 0.5, axis: worldUpDirection)
        cameraController.update()
        
        lightHolder.orientation = simd_quatf(angle: theta, axis: Satin.worldUpDirection)
        lightHolder.position = simd_make_float3(
            cos(theta) * 5,
            20 + sin(theta ) * 30,
            sin(theta) * 10
        )
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        sceneRenderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        let beautyTexture = postProcessedBeautyTexture(commandBuffer: commandBuffer)
        updatePreviewTextures(beautyTexture: beautyTexture)

        overlayRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: overlayScene,
            camera: overlayCamera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / max(size.height, 1.0)
        sceneRenderer.resize(size)
        ssaoPostProcessor.resize(size: size, scaleFactor: scaleFactor)
        motionBlurPostProcessor.resize(size: size, scaleFactor: scaleFactor)
        bokehDepthOfFieldPostProcessor.resize(size: size, scaleFactor: scaleFactor)
        overlayRenderer.resize(size)
        layoutOverlay(size: size)
    }

    private func setupLights() {
        
        let target = hasSceneBounds ? sceneBounds.center : simd_float3.zero
        let positions = [
            simd_make_float3(0.0, 300.0, -200.0),
            simd_make_float3(-50.0, 100.0, 0.0),
            simd_make_float3(50.0, 20.0, 0.0),
            simd_make_float3(0.0, 20.0, 100.0)
        ]
        
        let ups = [
            Satin.worldUpDirection,
            Satin.worldRightDirection,
            Satin.worldRightDirection,
            Satin.worldUpDirection
        ]
        
        for (index, position) in positions.enumerated() {
            let light = PointLight(context: defaultContext, color: .one, intensity: 100)
            light.position = position
            light.radius = 300
            light.shadow.resolution = (width: 512, height: 512)
            light.lookAt(target: target, up: ups[index])
            light.castShadow = true
            lightHolder.add(light)
        }
    }

    private func setupSuzanneScene() {
        let url = modelsURL.appendingPathComponent("Suzanne").appendingPathComponent("Suzanne.obj")
        guard let model = loadAsset(url: url, context: defaultContext) else { return }

        var monkey: Mesh?
        model.apply { object in
            if let mesh = object as? Mesh {
                monkey = mesh
            }
        }

        guard let monkey else { return }

        monkey.material = material
        self.model = monkey
        sceneBounds = monkey.worldBounds
        scene.add(monkey)
    }

    private func setupTextures() {
        let cubeDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .r32Float, size: 1, mipmapped: false)
        let cubeTexture = device.makeTexture(descriptor: cubeDescriptor)
        material.setTexture(cubeTexture, type: .reflection)
        material.setTexture(cubeTexture, type: .irradiance)

        let tempDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        let tempTexture = device.makeTexture(descriptor: tempDescriptor)
        material.setTexture(tempTexture, type: .brdf)
        material.setTexture(tempTexture, type: .baseColor)
        material.setTexture(tempTexture, type: .occlusion)
        material.setTexture(tempTexture, type: .metallic)
        material.setTexture(tempTexture, type: .normal)
        material.setTexture(tempTexture, type: .roughness)

        let baseURL = modelsURL.appendingPathComponent("Suzanne")
        let maps: [PBRTextureType: URL] = [
            .baseColor: baseURL.appendingPathComponent("albedo.png"),
            .occlusion: baseURL.appendingPathComponent("ao.png"),
            .metallic: baseURL.appendingPathComponent("metallic.png"),
            .normal: baseURL.appendingPathComponent("normal.png"),
            .roughness: baseURL.appendingPathComponent("roughness.png")
        ]

        let loader = MTKTextureLoader(device: device)
        do {
            for (type, url) in maps {
                let texture = try loader.newTexture(URL: url, options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically
                ])
                material.setTexture(texture, type: type)
            }
        } catch {
            print(error.localizedDescription)
        }
    }

    private func frameScene(bounds: Bounds) {
        let size = bounds.size
        let radius = max(max(size.x, size.y), size.z) * 0.5
        let distance = max(radius * 1.2, 6.0)
        let target = bounds.center + simd_make_float3(0.0, size.y * 0.05, 0.0)

        camera.near = max(distance * 0.001, 0.01)
        camera.far = max(distance * 16.0, 1000.0)
        camera.position = target + simd_make_float3(0.0, size.y * 0.08, distance)
        camera.lookAt(target: target)
    }

    private func loadHdri() {
        let url = texturesURL.appendingPathComponent("brown_photostudio_02_2k.hdr")
        if let hdr = loadHDR(device: device, url: url) {
            scene.setEnvironment(texture: hdr)
        }
    }

    private func setupOverlayScene() {
        overlayScene.add(beautyMesh)
        overlayScene.add(previewStripBackground)

        outputPreviews = PreviewOutput.allCases.map(makePreview(for:))
        for preview in outputPreviews {
//            overlayScene.add(preview.background)
            overlayScene.add(preview.mesh)
            if let label = preview.label {
                overlayScene.add(label)
            }
        }
    }

    private func makePreview(for output: PreviewOutput) -> OutputPreview {
        let previewMaterial: Material
        switch output {
//        case .depth:
//            let material = SourceMaterial(
//                context: overlayContext,
//                pipelineURL: sharedAssetsURL
//                    .appendingPathComponent("Pipelines")
//                    .appendingPathComponent("ShadowPost")
//                    .appendingPathComponent("Shaders.metal")
//            )
//            material.blending = .disabled
//            material.depthWriteEnabled = false
//            material.set("Color", simd_float4.one)
//            previewMaterial = material
        default:
            let material = BasicTextureMaterial(context: overlayContext)
            material.blending = .disabled
            material.depthWriteEnabled = false
            previewMaterial = material
        }

        let previewMesh = Mesh(
            context: overlayContext,
            label: "\(output.title) Preview",
            geometry: previewGeometry,
            material: previewMaterial,
            renderOrder: 30
        )
        configureOverlay(previewMesh)

//        let backgroundMesh = Mesh(
//            context: overlayContext,
//            label: "\(output.title) Preview Background",
//            geometry: previewGeometry,
//            material: previewTileMaterial,
//            renderOrder: 20
//        )
//        configureOverlay(backgroundMesh)

        let labelMesh: TextMesh?
        if let fontAtlas = overlayFontAtlas, let labelMaterial = overlayLabelMaterial {
            let geometry = TextGeometry(context: overlayContext, text: output.title, font: fontAtlas)
            let textMesh = TextMesh(
                context: overlayContext,
                label: "\(output.title) Label",
                geometry: geometry,
                material: labelMaterial
            )
            textMesh.renderOrder = 40
            configureOverlay(textMesh)
            labelMesh = textMesh
        } else {
            labelMesh = nil
        }

        return OutputPreview(
            output: output,
//            background: backgroundMesh,
            mesh: previewMesh,
            label: labelMesh
        )
    }

    private func postProcessedBeautyTexture(commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        ssaoPostProcessor.colorTexture = sceneRenderer.colorTexture
        ssaoPostProcessor.depthTexture = sceneRenderer.depthTexture
        ssaoPostProcessor.normalTexture = sceneRenderer.normalTexture
        ssaoPostProcessor.sceneCamera = camera
        ssaoPostProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)

        let compositeTexture = ssaoPostProcessor.outputTexture ?? sceneRenderer.colorTexture

        motionBlurPostProcessor.colorTexture = compositeTexture
        motionBlurPostProcessor.velocityTexture = sceneRenderer.velocityTexture
        motionBlurPostProcessor.depthTexture = sceneRenderer.depthTexture
        motionBlurPostProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)

        let motionBlurTexture = motionBlurPostProcessor.outputTexture ?? compositeTexture

        bokehDepthOfFieldPostProcessor.colorTexture = motionBlurTexture
        bokehDepthOfFieldPostProcessor.depthTexture = sceneRenderer.depthTexture
        bokehDepthOfFieldPostProcessor.sceneCamera = camera
        bokehDepthOfFieldPostProcessor.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer
        )

        return bokehDepthOfFieldPostProcessor.outputTexture ?? motionBlurTexture
    }

    private func updatePreviewTextures(beautyTexture: MTLTexture?) {
        beautyMaterial.texture = beautyTexture

        for preview in outputPreviews {
            let isVisible: Bool

            switch preview.output {
//            case .depth:
//                let depthTexture = sceneRenderer.depthTexture
//                preview.mesh.material?.set(sceneRenderer.colorTexture, index: FragmentTextureIndex.Custom0)
//                preview.mesh.material?.set(depthTexture, index: FragmentTextureIndex.Custom1)
//                preview.mesh.material?.set("Near Far", [camera.near, camera.far])
//                isVisible = depthTexture != nil
            default:
                let texture = texture(for: preview.output)
                if let material = preview.mesh.material as? BasicTextureMaterial {
                    material.texture = texture
                }
                isVisible = texture != nil
            }

//            preview.background.visible = isVisible
            preview.mesh.visible = isVisible
            preview.label?.visible = isVisible
        }
    }

    private func texture(for output: PreviewOutput) -> MTLTexture? {
        switch output {
        case .color:
            return sceneRenderer.colorTexture
        case .depth:
            return sceneRenderer.depthTexture
        case .albedo:
            return sceneRenderer.albedoTexture
        case .normals:
            return sceneRenderer.normalTexture
        case .pbr:
            return sceneRenderer.pbrTexture
        case .velocity:
            return sceneRenderer.velocityTexture
        case .emissive:
            return sceneRenderer.emissiveTexture
        }
    }

    private func layoutOverlay(size: (width: Float, height: Float)) {
        let width = max(size.width, 1.0)
        let height = max(size.height, 1.0)
        let aspect = width / height

        overlayCamera.position = [0.0, 0.0, 10.0]
        overlayCamera.update(left: 0.0, right: width, bottom: 0.0, top: height, near: 0.0, far: 20.0)

        beautyMesh.position = [width * 0.5, height * 0.5, 0.0]
        beautyMesh.scale = [width, height, 1.0]

        let previewCount = Float(outputPreviews.count)
        guard previewCount > 0 else { return }

        let inset = max(18.0, min(width, height) * 0.03)
        let gap = max(10.0, min(width, height) * 0.012)
        let availableWidth = width - inset * 2.0 - gap * (previewCount - 1.0)

        var previewWidth = min(availableWidth / previewCount, width * 0.22)
        var previewHeight = previewWidth / max(aspect, 0.1)
        let maxPreviewHeight = min(height * 0.2, 140.0)
        if previewHeight > maxPreviewHeight {
            previewHeight = maxPreviewHeight
            previewWidth = previewHeight * aspect
        }

        let labelHeight = overlayFontAtlas.map { min(max(previewHeight * 0.16, 12.0), Float($0.size) * 0.45) } ?? 0.0
        let labelGap: Float = labelHeight > 0.0 ? max(6.0, previewHeight * 0.08) : 0.0
        let stripPadding = max(10.0, previewHeight * 0.08)
        let tileBorder = max(4.0, previewHeight * 0.05)

        let totalWidth = previewWidth * previewCount + gap * (previewCount - 1.0)
        let stripHeight = stripPadding * 2.0 + previewHeight + labelGap + labelHeight
        let stripCenterY = inset + stripHeight * 0.5
        let tileBottom = stripCenterY - stripHeight * 0.5 + stripPadding
        let tileCenterY = tileBottom + previewHeight * 0.5

        previewStripBackground.position = [width * 0.5, stripCenterY, 0.5]
        previewStripBackground.scale = [totalWidth + stripPadding * 2.0, stripHeight, 1.0]

        let startX = width * 0.5 - totalWidth * 0.5 + previewWidth * 0.5

        for (index, preview) in outputPreviews.enumerated() {
            let centerX = startX + Float(index) * (previewWidth + gap)

//            preview.background.position = [centerX, tileCenterY, 1.0]
//            preview.background.scale = [previewWidth + tileBorder * 2.0, previewHeight + tileBorder * 2.0, 1.0]

            preview.mesh.position = [centerX, tileCenterY, 1.5]
            preview.mesh.scale = [previewWidth, previewHeight, 1.0]

            if let label = preview.label, let fontAtlas = overlayFontAtlas {
                let textScale = labelHeight / Float(fontAtlas.size)
                label.scale = [textScale, textScale, 1.0]
                label.position = [centerX, tileBottom + previewHeight + labelGap + labelHeight * 0.5, 2.0]
            }
        }
    }

    private func makeOverlayColorMaterial(_ color: simd_float4) -> BasicColorMaterial {
        let material = BasicColorMaterial(context: overlayContext, color: color)
        material.depthWriteEnabled = false
        return material
    }

    private func configureOverlay(_ mesh: Mesh) {
        mesh.castShadow = false
        mesh.receiveShadow = false
        mesh.cullMode = .none
    }
}
