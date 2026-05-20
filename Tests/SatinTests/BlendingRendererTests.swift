import Metal
import Satin
import XCTest

final class BlendingRendererTests: XCTestCase {
    func testAlphaBlendedDiffuseMatchesForwardAcrossModes() throws {
        let forward = try renderBlendingScene(mode: .forward) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(0.95, 0.32, 0.18, 0.35),
                blending: .alpha,
                hardness: 0.55
            )
        }

        let forwardPlus = try renderBlendingScene(mode: .forwardPlus) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(0.95, 0.32, 0.18, 0.35),
                blending: .alpha,
                hardness: 0.55
            )
        }

        let deferred = try renderBlendingScene(mode: .deferredGeometry) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(0.95, 0.32, 0.18, 0.35),
                blending: .alpha,
                hardness: 0.55
            )
        }

        VisualTestHarness.assertContainsVisibleContent(forward, minimumChangedPixelRatio: 0.08, minimumMeanNormalizedDifference: 0.01)
        assertImagesMatch(forwardPlus, forward, threshold: 0.01)
        assertImagesMatch(deferred, forward, threshold: 0.01)
    }

    func testAlphaBlendedPhysicalMatchesForwardAcrossModes() throws {
        let forward = try renderBlendingScene(mode: .forward) { context in
            let material = StandardMaterial(
                context: context,
                baseColor: simd_float4(0.92, 0.76, 0.24, 0.4),
                metallic: 0.65,
                roughness: 0.28,
                specular: 0.85,
                occlusion: 1.0,
                emissiveColor: .zero
            )
            material.blending = .alpha
            return material
        }

        let forwardPlus = try renderBlendingScene(mode: .forwardPlus) { context in
            let material = StandardMaterial(
                context: context,
                baseColor: simd_float4(0.92, 0.76, 0.24, 0.4),
                metallic: 0.65,
                roughness: 0.28,
                specular: 0.85,
                occlusion: 1.0,
                emissiveColor: .zero
            )
            material.blending = .alpha
            return material
        }

        let deferred = try renderBlendingScene(mode: .deferredGeometry) { context in
            let material = StandardMaterial(
                context: context,
                baseColor: simd_float4(0.92, 0.76, 0.24, 0.4),
                metallic: 0.65,
                roughness: 0.28,
                specular: 0.85,
                occlusion: 1.0,
                emissiveColor: .zero
            )
            material.blending = .alpha
            return material
        }

        VisualTestHarness.assertContainsVisibleContent(forward, minimumChangedPixelRatio: 0.08, minimumMeanNormalizedDifference: 0.01)
        assertImagesMatch(forwardPlus, forward, threshold: 0.01)
        assertImagesMatch(deferred, forward, threshold: 0.01)
    }

    func testAdditiveBlendedDiffuseMatchesForwardAcrossModes() throws {
        let forward = try renderBlendingScene(mode: .forward) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(1.0, 0.45, 0.12, 0.45),
                blending: .additive,
                hardness: 0.7
            )
        }

        let forwardPlus = try renderBlendingScene(mode: .forwardPlus) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(1.0, 0.45, 0.12, 0.45),
                blending: .additive,
                hardness: 0.7
            )
        }

        let deferred = try renderBlendingScene(mode: .deferredGeometry) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(1.0, 0.45, 0.12, 0.45),
                blending: .additive,
                hardness: 0.7
            )
        }

        VisualTestHarness.assertContainsVisibleContent(forward, minimumChangedPixelRatio: 0.08, minimumMeanNormalizedDifference: 0.01)
        assertImagesMatch(forwardPlus, forward, threshold: 0.01)
        assertImagesMatch(deferred, forward, threshold: 0.01)
    }

    func testOverlappingAlphaLayersMatchForwardAcrossModes() throws {
        let forward = try renderOverlappingAlphaStack(mode: .forward)
        let forwardPlus = try renderOverlappingAlphaStack(mode: .forwardPlus)
        let deferred = try renderOverlappingAlphaStack(mode: .deferredGeometry)

        VisualTestHarness.assertContainsVisibleContent(forward, minimumChangedPixelRatio: 0.08, minimumMeanNormalizedDifference: 0.01)
        assertImagesMatch(forwardPlus, forward, threshold: 0.01)
        assertImagesMatch(deferred, forward, threshold: 0.01)
    }

    func testAlphaOitMatchesAcrossTransparentDrawOrder() throws {
        let forwardReference = try renderOverlappingAlphaStack(mode: .forward, drawNearPlaneFirst: false)
        let reorderedForward = try renderOverlappingAlphaStack(mode: .forward, drawNearPlaneFirst: true)
        let reorderedForwardPlus = try renderOverlappingAlphaStack(mode: .forwardPlus, drawNearPlaneFirst: true)
        let reorderedDeferred = try renderOverlappingAlphaStack(mode: .deferredGeometry, drawNearPlaneFirst: true)

        assertImagesMatch(reorderedForward, forwardReference, threshold: 0.01)
        assertImagesMatch(reorderedForwardPlus, forwardReference, threshold: 0.01)
        assertImagesMatch(reorderedDeferred, forwardReference, threshold: 0.01)
    }

    func testTransparentOnlyAlphaSceneMatchesForwardAcrossModes() throws {
        let forward = try renderTransparentOnlyAlphaScene(mode: .forward)
        let forwardPlus = try renderTransparentOnlyAlphaScene(mode: .forwardPlus)
        let deferred = try renderTransparentOnlyAlphaScene(mode: .deferredGeometry)

        VisualTestHarness.assertContainsVisibleContent(forward, minimumChangedPixelRatio: 0.02, minimumMeanNormalizedDifference: 0.005)
        assertRGBImagesMatch(forwardPlus, forward, threshold: 0.01)
        assertRGBImagesMatch(deferred, forward, threshold: 0.01)
    }

    func testSwitchingBlendModesRebuildsTransparentRenderingCorrectly() throws {
        let disabledReference = try renderBlendingScene(mode: .forward) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(0.95, 0.32, 0.18, 0.35),
                blending: .disabled,
                hardness: 0.55
            )
        }

        let alphaReference = try renderBlendingScene(mode: .forward) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(0.95, 0.32, 0.18, 0.35),
                blending: .alpha,
                hardness: 0.55
            )
        }

        let additiveReference = try renderBlendingScene(mode: .forward) { context in
            BasicDiffuseMaterial(
                context: context,
                color: simd_float4(0.95, 0.32, 0.18, 0.35),
                blending: .additive,
                hardness: 0.55
            )
        }

        let switchedImages = try renderBlendModeSwitchSequence()
        assertImagesMatch(switchedImages[0], disabledReference, threshold: 0.01)
        assertImagesMatch(switchedImages[1], alphaReference, threshold: 0.01)
        assertImagesMatch(switchedImages[2], additiveReference, threshold: 0.01)
    }
}

private func renderBlendingScene(
    mode: RenderingMode,
    foregroundMaterial: (Context) -> Material
) throws -> RGBAImage {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw NSError(domain: "BlendingRendererTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal unavailable"])
    }

    guard let commandQueue = device.makeCommandQueue() else {
        throw NSError(domain: "BlendingRendererTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create command queue"])
    }

    let size = SIMD2<Int>(192, 192)
    let activeOutputs: RendererOutputs = mode == .forward ? [.color] : [.color, .albedo, .normals, .pbr, .velocity, .emissive]
    let context = Context(
        device: device,
        sampleCount: 1,
        colorPixelFormat: .bgra8Unorm,
        depthPixelFormat: .depth32Float,
        renderingMode: mode,
        activeOutputs: activeOutputs
    )

    let renderer = RenderEncoder(
        context: context,
        clearColor: VisualTestHarness.defaultClearColor,
        frameBufferOnly: false
    )
    renderer.resize((width: Float(size.x), height: Float(size.y)))

    let camera = PerspectiveCamera(context: context, position: [0.0, 0.0, 4.5], near: 0.1, far: 100.0, fov: 30.0)
    camera.aspect = Float(size.x) / Float(size.y)
    camera.lookAt(target: [0.0, 0.0, 0.0])

    let scene = Object(context: context, label: "Blend Scene")

    let directional = DirectionalLight(context: context, color: simd_float3(1.0, 0.98, 0.95), intensity: 1.35)
    directional.position = [1.4, 1.8, 2.8]
    directional.lookAt(target: [0.0, 0.0, 0.0])

    let backgroundMaterial = BasicColorMaterial(
        context: context,
        color: simd_float4(0.08, 0.22, 0.66, 1.0),
        blending: .disabled
    )
    let background = Mesh(
        context: context,
        label: "Background",
        geometry: PlaneGeometry(context: context, width: 3.0, height: 3.0, orientation: .xy),
        material: backgroundMaterial
    )
    background.position = [0.0, 0.0, -0.2]
    background.renderOrder = 0

    let foreground = Mesh(
        context: context,
        label: "Foreground",
        geometry: PlaneGeometry(context: context, width: 1.7, height: 1.7, orientation: .xy),
        material: foregroundMaterial(context)
    )
    foreground.position = [0.0, 0.0, 0.15]
    foreground.renderOrder = 1

    scene.add(directional)
    scene.add(background)
    scene.add(foreground)

    let outputTexture = try makeReadableColorTexture(device: device, size: size)
    try drawFrame(renderer: renderer, commandQueue: commandQueue, scene: scene, camera: camera, renderTarget: outputTexture)
    return try VisualTestHarness.image(from: outputTexture)
}

private func assertImagesMatch(
    _ rendered: RGBAImage,
    _ reference: RGBAImage,
    threshold: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let diff = VisualTestHarness.diff(rendered: rendered, reference: reference)
    XCTAssertLessThanOrEqual(
        diff.meanAbsoluteDifference,
        threshold,
        "meanAbsoluteDifference: \(diff.meanAbsoluteDifference), threshold: \(threshold), maxAbsoluteDifference: \(diff.maxAbsoluteDifference)",
        file: file,
        line: line
    )
}

private func assertRGBImagesMatch(
    _ rendered: RGBAImage,
    _ reference: RGBAImage,
    threshold: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(rendered.width, reference.width, file: file, line: line)
    XCTAssertEqual(rendered.height, reference.height, file: file, line: line)

    let pixelCount = min(rendered.width * rendered.height, reference.width * reference.height)
    let rgbSampleCount = pixelCount * 3
    var totalDifference = 0
    var maxDifference = 0

    for pixelIndex in 0..<pixelCount {
        let base = pixelIndex * 4
        for channel in 0..<3 {
            let difference = abs(Int(rendered.pixels[base + channel]) - Int(reference.pixels[base + channel]))
            totalDifference += difference
            maxDifference = max(maxDifference, difference)
        }
    }

    let meanAbsoluteDifference = Double(totalDifference) / Double(rgbSampleCount * 255)
    XCTAssertLessThanOrEqual(
        meanAbsoluteDifference,
        threshold,
        "rgb meanAbsoluteDifference: \(meanAbsoluteDifference), threshold: \(threshold), rgb maxAbsoluteDifference: \(maxDifference)",
        file: file,
        line: line
    )
}

private func drawFrame(
    renderer: RenderEncoder,
    commandQueue: MTLCommandQueue,
    scene: Object,
    camera: Camera,
    renderTarget: MTLTexture,
    synchronizeTextures: [MTLTexture] = []
) throws {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
        throw NSError(domain: "BlendingRendererTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer"])
    }

    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderer.draw(
        renderPassDescriptor: renderPassDescriptor,
        commandBuffer: commandBuffer,
        scene: scene,
        camera: camera,
        renderTarget: renderTarget
    )

    if readableTextureStorageMode == .managed,
       !synchronizeTextures.isEmpty,
       let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
        for texture in synchronizeTextures {
            blitEncoder.synchronize(resource: texture)
        }
        blitEncoder.endEncoding()
    }

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    if let error = commandBuffer.error {
        throw error
    }
}

private func makeReadableColorTexture(device: MTLDevice, size: SIMD2<Int>) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: size.x,
        height: size.y,
        mipmapped: false
    )
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = readableTextureStorageMode

    guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw NSError(domain: "BlendingRendererTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create color render target"])
    }

    return texture
}

private func renderOverlappingAlphaStack(
    mode: RenderingMode,
    drawNearPlaneFirst: Bool = false
) throws -> RGBAImage {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeCommandQueue()
    else {
        throw NSError(domain: "BlendingRendererTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Metal unavailable"])
    }

    let size = SIMD2<Int>(192, 192)
    let activeOutputs: RendererOutputs = mode == .forward ? [.color] : [.color, .albedo, .normals, .pbr, .velocity, .emissive]
    let context = Context(
        device: device,
        sampleCount: 1,
        colorPixelFormat: .bgra8Unorm,
        depthPixelFormat: .depth32Float,
        renderingMode: mode,
        activeOutputs: activeOutputs
    )

    let renderer = RenderEncoder(
        context: context,
        clearColor: VisualTestHarness.defaultClearColor,
        frameBufferOnly: false
    )
    renderer.resize((width: Float(size.x), height: Float(size.y)))

    let camera = PerspectiveCamera(context: context, position: [0.0, 0.0, 4.5], near: 0.1, far: 100.0, fov: 30.0)
    camera.aspect = Float(size.x) / Float(size.y)
    camera.lookAt(target: [0.0, 0.0, 0.0])

    let scene = Object(context: context, label: "Alpha Stack Scene")

    let backgroundMaterial = BasicColorMaterial(
        context: context,
        color: simd_float4(0.1, 0.1, 0.18, 1.0),
        blending: .disabled
    )
    let background = Mesh(
        context: context,
        label: "Background",
        geometry: PlaneGeometry(context: context, width: 3.0, height: 3.0, orientation: .xy),
        material: backgroundMaterial
    )
    background.position = [0.0, 0.0, -0.3]

    let nearMaterial = BasicColorMaterial(
        context: context,
        color: simd_float4(0.92, 0.34, 0.16, 0.45),
        blending: .alpha
    )
    let farMaterial = BasicColorMaterial(
        context: context,
        color: simd_float4(0.15, 0.72, 0.95, 0.35),
        blending: .alpha
    )

    let nearPlane = Mesh(
        context: context,
        label: "Near Plane",
        geometry: PlaneGeometry(context: context, width: 1.6, height: 1.6, orientation: .xy),
        material: nearMaterial
    )
    nearPlane.position = [-0.15, 0.0, 0.2]
    nearPlane.renderOrder = drawNearPlaneFirst ? 1 : 2

    let farPlane = Mesh(
        context: context,
        label: "Far Plane",
        geometry: PlaneGeometry(context: context, width: 1.6, height: 1.6, orientation: .xy),
        material: farMaterial
    )
    farPlane.position = [0.18, 0.0, -0.05]
    farPlane.renderOrder = drawNearPlaneFirst ? 2 : 1

    scene.add(background)
    scene.add(nearPlane)
    scene.add(farPlane)

    let outputTexture = try makeReadableColorTexture(device: device, size: size)
    try drawFrame(renderer: renderer, commandQueue: commandQueue, scene: scene, camera: camera, renderTarget: outputTexture)
    return try VisualTestHarness.image(from: outputTexture)
}

private func renderBlendModeSwitchSequence() throws -> [RGBAImage] {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeCommandQueue()
    else {
        throw NSError(domain: "BlendingRendererTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Metal unavailable"])
    }

    let size = SIMD2<Int>(192, 192)
    let context = Context(
        device: device,
        sampleCount: 1,
        colorPixelFormat: .bgra8Unorm,
        depthPixelFormat: .depth32Float,
        renderingMode: .forward,
        activeOutputs: [.color]
    )

    let renderer = RenderEncoder(
        context: context,
        clearColor: VisualTestHarness.defaultClearColor,
        frameBufferOnly: false
    )
    renderer.resize((width: Float(size.x), height: Float(size.y)))

    let camera = PerspectiveCamera(context: context, position: [0.0, 0.0, 4.5], near: 0.1, far: 100.0, fov: 30.0)
    camera.aspect = Float(size.x) / Float(size.y)
    camera.lookAt(target: [0.0, 0.0, 0.0])

    let scene = Object(context: context, label: "Blend Switch Scene")
    let directional = DirectionalLight(context: context, color: simd_float3(1.0, 0.98, 0.95), intensity: 1.35)
    directional.position = [1.4, 1.8, 2.8]
    directional.lookAt(target: [0.0, 0.0, 0.0])

    let backgroundMaterial = BasicColorMaterial(
        context: context,
        color: simd_float4(0.08, 0.22, 0.66, 1.0),
        blending: .disabled
    )
    let background = Mesh(
        context: context,
        label: "Background",
        geometry: PlaneGeometry(context: context, width: 3.0, height: 3.0, orientation: .xy),
        material: backgroundMaterial
    )
    background.position = [0.0, 0.0, -0.2]

    let foregroundMaterial = BasicDiffuseMaterial(
        context: context,
        color: simd_float4(0.95, 0.32, 0.18, 0.35),
        blending: .disabled,
        hardness: 0.55
    )
    let foreground = Mesh(
        context: context,
        label: "Foreground",
        geometry: PlaneGeometry(context: context, width: 1.7, height: 1.7, orientation: .xy),
        material: foregroundMaterial
    )
    foreground.position = [0.0, 0.0, 0.15]

    scene.add(directional)
    scene.add(background)
    scene.add(foreground)

    var images = [RGBAImage]()
    for blendMode in [Blending.disabled, .alpha, .additive] {
        foregroundMaterial.blending = blendMode
        let outputTexture = try makeReadableColorTexture(device: device, size: size)
        try drawFrame(renderer: renderer, commandQueue: commandQueue, scene: scene, camera: camera, renderTarget: outputTexture)
        images.append(try VisualTestHarness.image(from: outputTexture))
    }

    return images
}

private func renderTransparentOnlyAlphaScene(mode: RenderingMode) throws -> RGBAImage {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeCommandQueue()
    else {
        throw NSError(domain: "BlendingRendererTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Metal unavailable"])
    }

    let size = SIMD2<Int>(192, 192)
    let activeOutputs: RendererOutputs = mode == .forward ? [.color] : [.color, .albedo, .normals, .pbr, .velocity, .emissive]
    let context = Context(
        device: device,
        sampleCount: 1,
        colorPixelFormat: .bgra8Unorm,
        depthPixelFormat: .depth32Float,
        renderingMode: mode,
        activeOutputs: activeOutputs
    )

    let renderer = RenderEncoder(
        context: context,
        clearColor: simd_float4(0.0, 0.0, 0.0, 1.0),
        frameBufferOnly: false
    )
    renderer.resize((width: Float(size.x), height: Float(size.y)))

    let camera = PerspectiveCamera(context: context, position: [0.0, 0.0, 4.5], near: 0.1, far: 100.0, fov: 30.0)
    camera.aspect = Float(size.x) / Float(size.y)
    camera.lookAt(target: [0.0, 0.0, 0.0])

    let scene = Object(context: context, label: "Transparent Only Alpha Scene")
    let material = BasicDiffuseMaterial(
        context: context,
        color: simd_float4(0.08, 0.95, 0.95, 0.45),
        blending: .alpha,
        hardness: 0.6
    )
    let foreground = Mesh(
        context: context,
        label: "Transparent Foreground",
        geometry: PlaneGeometry(context: context, width: 1.6, height: 1.6, orientation: .xy),
        material: material
    )
    foreground.position = [0.0, 0.0, 0.0]
    scene.add(foreground)

    let outputTexture = try makeReadableColorTexture(device: device, size: size)
    try drawFrame(renderer: renderer, commandQueue: commandQueue, scene: scene, camera: camera, renderTarget: outputTexture)
    return try VisualTestHarness.image(from: outputTexture)
}

private var readableTextureStorageMode: MTLStorageMode {
    #if arch(x86_64)
    return .managed
    #else
    return .shared
    #endif
}
