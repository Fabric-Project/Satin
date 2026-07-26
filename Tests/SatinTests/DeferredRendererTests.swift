import Metal
import Satin
import XCTest

final class DeferredRendererTests: XCTestCase {
    func testRendererAllocatesDepthTextureWhenDepthActionsAreDontCare() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal unavailable")
            return
        }

        guard let commandQueue = device.makeCommandQueue() else {
            XCTFail("Failed to create command queue")
            return
        }

        let size = SIMD2<Int>(96, 96)
        let context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float
        )

        let renderer = RenderEncoder(
            context: context,
            clearColor: VisualTestHarness.defaultClearColor,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare,
            frameBufferOnly: false
        )
        renderer.resize((width: Float(size.x), height: Float(size.y)))
        renderer.depthTextureStorageMode = readableTextureStorageMode

        let camera = PerspectiveCamera(context: context, position: [0.0, 0.0, 4.0], near: 0.1, far: 100.0, fov: 30.0)
        camera.aspect = Float(size.x) / Float(size.y)
        camera.lookAt(target: .zero)

        let scene = Object(context: context, label: "Depth DontCare Scene")
        let mesh = Mesh(
            context: context,
            label: "Depth DontCare Mesh",
            geometry: PlaneGeometry(context: context, width: 1.8, height: 1.8, orientation: .xy),
            material: BasicColorMaterial(
                context: context,
                color: simd_float4(0.9, 0.4, 0.2, 1.0),
                blending: .disabled
            )
        )
        scene.add(mesh)

        let outputTexture = try makeReadableColorTexture(device: device, size: size)
        try drawFrame(renderer: renderer, commandQueue: commandQueue, scene: scene, camera: camera, renderTarget: outputTexture)

        XCTAssertNotNil(renderer.depthTexture)
        XCTAssertEqual(renderer.depthTexture?.pixelFormat, context.depthPixelFormat)
    }

    func testDeferredRendererPopulatesExpectedOutputs() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal unavailable")
            return
        }

        guard let commandQueue = device.makeCommandQueue() else {
            XCTFail("Failed to create command queue")
            return
        }

        let size = SIMD2<Int>(256, 192)
        let context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            renderingMode: .deferredGeometry,
            activeOutputs: [.color, .albedo, .normals, .pbr, .velocity, .emissive]
        )

        let renderer = RenderEncoder(
            context: context,
            clearColor: VisualTestHarness.defaultClearColor,
            frameBufferOnly: false
        )
        renderer.resize((width: Float(size.x), height: Float(size.y)))
        renderer.depthTextureStorageMode = readableTextureStorageMode
        renderer.albedoTextureStorageMode = readableTextureStorageMode
        renderer.normalTextureStorageMode = readableTextureStorageMode
        renderer.pbrTextureStorageMode = readableTextureStorageMode
        renderer.velocityTextureStorageMode = readableTextureStorageMode
        renderer.emissiveTextureStorageMode = readableTextureStorageMode

        let camera = PerspectiveCamera(context: context, position: [0.0, 0.15, 6.4], near: 0.1, far: 100.0, fov: 28.0)
        camera.aspect = Float(size.x) / Float(size.y)
        camera.lookAt(target: [0.0, -0.1, 0.0])

        let scene = Object(context: context, label: "Scene")

        let directional = DirectionalLight(context: context, color: simd_float3(1.0, 0.98, 0.95), intensity: 1.35)
        directional.position = [0.9, 2.4, 3.8]
        directional.lookAt(target: .zero)

        let point = PointLight(context: context, color: simd_float3(0.18, 0.5, 1.0), intensity: 2.4, radius: 9.0)
        point.position = [1.8, 1.25, 2.6]

        let metallicMaterial = StandardMaterial(
            context: context,
            baseColor: simd_float4(0.92, 0.28, 0.18, 1.0),
            metallic: 0.95,
            roughness: 0.16,
            specular: 1.0,
            occlusion: 1.0,
            emissiveColor: simd_float4(0.0, 0.0, 0.0, 1.0)
        )
        let moving = Mesh(
            context: context,
            label: "Moving Sphere",
            geometry: SphereGeometry(context: context, radius: 0.62, angularResolution: 32, verticalResolution: 18),
            material: metallicMaterial
        )
        moving.position = [-1.45, 0.02, 0.0]

        let matteMaterial = StandardMaterial(
            context: context,
            baseColor: simd_float4(0.22, 0.78, 0.3, 1.0),
            metallic: 0.02,
            roughness: 0.88,
            specular: 0.35,
            occlusion: 1.0,
            emissiveColor: simd_float4(0.0, 0.0, 0.0, 1.0)
        )
        let matteSphere = Mesh(
            context: context,
            label: "Matte Sphere",
            geometry: SphereGeometry(context: context, radius: 0.56, angularResolution: 32, verticalResolution: 18),
            material: matteMaterial
        )
        matteSphere.position = [0.0, 0.0, -0.1]

        let brushedMaterial = StandardMaterial(
            context: context,
            baseColor: simd_float4(0.88, 0.82, 0.28, 1.0),
            metallic: 0.58,
            roughness: 0.58,
            specular: 0.78,
            occlusion: 0.72,
            emissiveColor: simd_float4(0.0, 0.0, 0.0, 1.0)
        )
        let brushedSphere = Mesh(
            context: context,
            label: "Brushed Sphere",
            geometry: SphereGeometry(context: context, radius: 0.44, angularResolution: 32, verticalResolution: 18),
            material: brushedMaterial
        )
        brushedSphere.position = [0.45, 0.78, -0.55]

        let staticSphere = Mesh(
            context: context,
            label: "Diffuse Sphere",
            geometry: SphereGeometry(context: context, radius: 0.58, angularResolution: 32, verticalResolution: 18),
            material: BasicDiffuseMaterial(context: context, color: simd_float4(0.22, 0.74, 0.94, 1.0), blending: .disabled, hardness: 0.4)
        )
        staticSphere.position = [1.45, -0.05, -0.2]

        let emissiveMaterial = StandardMaterial(
            context: context,
            baseColor: simd_float4(0.14, 0.08, 0.04, 1.0),
            metallic: 0.0,
            roughness: 0.7,
            specular: 0.2,
            occlusion: 1.0,
            emissiveColor: simd_float4(1.0, 0.48, 0.08, 1.0)
        )
        let emissiveOrb = Mesh(
            context: context,
            label: "Emissive Orb",
            geometry: SphereGeometry(context: context, radius: 0.22, angularResolution: 24, verticalResolution: 12),
            material: emissiveMaterial
        )
        emissiveOrb.position = [0.0, 0.94, 0.24]

        let ground = Mesh(
            context: context,
            label: "Ground",
            geometry: PlaneGeometry(context: context, size: 6.4, orientation: .zx),
            material: BasicDiffuseMaterial(context: context, color: simd_float4(0.18, 0.2, 0.24, 1.0), blending: .disabled, hardness: 0.18)
        )
        ground.position.y = -0.94

        scene.add(directional)
        scene.add(point)
        scene.add(ground)
        scene.add(moving)
        scene.add(matteSphere)
        scene.add(brushedSphere)
        scene.add(staticSphere)
        scene.add(emissiveOrb)

        let outputTexture = try makeReadableColorTexture(device: device, size: size)

        try drawFrame(renderer: renderer, commandQueue: commandQueue, scene: scene, camera: camera, renderTarget: outputTexture)

        moving.position.x += 0.28
        camera.position.x += 0.06
        camera.lookAt(target: [0.08, -0.1, 0.0])

        try drawFrame(
            renderer: renderer,
            commandQueue: commandQueue,
            scene: scene,
            camera: camera,
            renderTarget: outputTexture,
            synchronizeTextures: [
                outputTexture,
                renderer.albedoTexture,
                renderer.normalTexture,
                renderer.pbrTexture,
                renderer.velocityTexture,
                renderer.emissiveTexture,
            ].compactMap { $0 }
        )

        guard let depthTexture = renderer.depthTexture,
              let albedoTexture = renderer.albedoTexture,
              let normalTexture = renderer.normalTexture,
              let pbrTexture = renderer.pbrTexture,
              let velocityTexture = renderer.velocityTexture,
              let emissiveTexture = renderer.emissiveTexture
        else {
            XCTFail("Deferred renderer did not allocate expected output textures")
            return
        }

        XCTAssertEqual(depthTexture.pixelFormat, context.depthPixelFormat)
        XCTAssertEqual(albedoTexture.pixelFormat, context.albedoPixelFormat)
        XCTAssertEqual(normalTexture.pixelFormat, context.normalsPixelFormat)
        XCTAssertEqual(pbrTexture.pixelFormat, context.pbrPixelFormat)
        XCTAssertEqual(velocityTexture.pixelFormat, context.velocityPixelFormat)
        XCTAssertEqual(emissiveTexture.pixelFormat, context.emissivePixelFormat)

        let colorImage = try VisualTestHarness.image(from: outputTexture)
        let albedoImage = try visualizeColorTexture(device: device, commandQueue: commandQueue, texture: albedoTexture, size: size)
        let normalImage = try visualizeColorTexture(device: device, commandQueue: commandQueue, texture: normalTexture, size: size)
        let pbrImage = try visualizeColorTexture(device: device, commandQueue: commandQueue, texture: pbrTexture, size: size)
        let roughnessImage = try visualizeTextureChannel(device: device, commandQueue: commandQueue, texture: pbrTexture, size: size, channel: 0)
        let metallicImage = try visualizeTextureChannel(device: device, commandQueue: commandQueue, texture: pbrTexture, size: size, channel: 1)
        let aoImage = try visualizeTextureChannel(device: device, commandQueue: commandQueue, texture: pbrTexture, size: size, channel: 2)
        let velocityImage = try visualizeVelocityTexture(device: device, commandQueue: commandQueue, texture: velocityTexture, size: size)
        let emissiveImage = try visualizeColorTexture(device: device, commandQueue: commandQueue, texture: emissiveTexture, size: size)
        let depthImage = try visualizeDepthTexture(device: device, commandQueue: commandQueue, depthTexture: depthTexture, size: size)

        try VisualTestHarness.assertVisualMatch(colorImage, reference: .bundle(name: "deferred-color"), threshold: 0.004)

        let albedoCoverage = imageCoverage(albedoImage, baseline: [0, 0, 0, 255])
        XCTAssertGreaterThan(albedoCoverage.changedPixelRatio, 0.12)
        XCTAssertGreaterThan(albedoCoverage.meanNormalizedDifference, 0.03)
        try VisualTestHarness.assertVisualMatch(albedoImage, reference: .bundle(name: "deferred-albedo"), threshold: 0.004)

        let normalCoverage = imageCoverage(normalImage, baseline: [0, 0, 0, 255])
        XCTAssertGreaterThan(normalCoverage.changedPixelRatio, 0.12)
        XCTAssertGreaterThan(normalCoverage.meanNormalizedDifference, 0.05)
        try VisualTestHarness.assertVisualMatch(normalImage, reference: .bundle(name: "deferred-normals"), threshold: 0.004)

        let pbrCoverage = imageCoverage(pbrImage, baseline: [0, 0, 0, 255])
        XCTAssertGreaterThan(pbrCoverage.changedPixelRatio, 0.12)
        XCTAssertGreaterThan(pbrCoverage.meanNormalizedDifference, 0.05)
        try VisualTestHarness.assertVisualMatch(pbrImage, reference: .bundle(name: "deferred-pbr"), threshold: 0.004)
        try VisualTestHarness.assertVisualMatch(roughnessImage, reference: .bundle(name: "deferred-pbr-roughness"), threshold: 0.004)
        try VisualTestHarness.assertVisualMatch(metallicImage, reference: .bundle(name: "deferred-pbr-metallic"), threshold: 0.004)
        try VisualTestHarness.assertVisualMatch(aoImage, reference: .bundle(name: "deferred-pbr-ao"), threshold: 0.004)

        let velocityCoverage = imageCoverage(velocityImage, baseline: [0, 0, 0, 255])
        XCTAssertGreaterThan(velocityCoverage.changedPixelRatio, 0.002)
        XCTAssertGreaterThan(velocityCoverage.meanNormalizedDifference, 0.001)
        try VisualTestHarness.assertVisualMatch(velocityImage, reference: .bundle(name: "deferred-velocity"), threshold: 0.004)

        try VisualTestHarness.assertVisualMatch(emissiveImage, reference: .bundle(name: "deferred-emissive"), threshold: 0.004)

        let depthCoverage = imageCoverage(depthImage, baseline: [0, 0, 0, 255])
        XCTAssertGreaterThan(depthCoverage.changedPixelRatio, 0.12)
        XCTAssertGreaterThan(depthCoverage.meanNormalizedDifference, 0.005)
        try VisualTestHarness.assertVisualMatch(depthImage, reference: .bundle(name: "deferred-depth"), threshold: 0.004)
    }
}

private struct ImageCoverage {
    let changedPixelCount: Int
    let totalPixelCount: Int
    let changedPixelRatio: Double
    let meanNormalizedDifference: Double
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
        throw NSError(domain: "DeferredRendererTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer"])
    }

    let renderPassDescriptor = MTLRenderPassDescriptor()
    try renderer.draw(
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
        throw NSError(domain: "DeferredRendererTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create color render target"])
    }

    return texture
}

private func visualizeColorTexture(
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    texture: MTLTexture,
    size: SIMD2<Int>
) throws -> RGBAImage {
    let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut vizVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        const float2 uvs[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };

        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment half4 vizFragment(VertexOut in [[stage_in]], texture2d<float> inputTexture [[texture(0)]]) {
        constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float4 value = inputTexture.sample(inputSampler, in.uv);
        return half4(half3(saturate(value.rgb)), 1.0h);
    }
    """

    return try visualizeTexture(device: device, commandQueue: commandQueue, source: source, fragmentName: "vizFragment", texture: texture, size: size)
}

private func visualizeVelocityTexture(
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    texture: MTLTexture,
    size: SIMD2<Int>
) throws -> RGBAImage {
    let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut vizVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        const float2 uvs[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };

        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment half4 vizFragment(VertexOut in [[stage_in]], texture2d<float> inputTexture [[texture(0)]]) {
        constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float2 velocity = inputTexture.sample(inputSampler, in.uv).rg;
        float magnitude = saturate(length(velocity) * 12.0);
        float3 color = float3(
            saturate(velocity.x * 24.0 + 0.5),
            saturate(-velocity.y * 24.0 + 0.5),
            magnitude
        );
        return half4(half3(color), 1.0h);
    }
    """

    return try visualizeTexture(device: device, commandQueue: commandQueue, source: source, fragmentName: "vizFragment", texture: texture, size: size)
}

private func visualizeTexture(
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    source: String,
    fragmentName: String,
    texture: MTLTexture,
    size: SIMD2<Int>
) throws -> RGBAImage {
    let library = try device.makeLibrary(source: source, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "vizVertex")
    descriptor.fragmentFunction = library.makeFunction(name: fragmentName)
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let outputTexture = try makeReadableColorTexture(device: device, size: size)

    let renderPassDescriptor = MTLRenderPassDescriptor()
    guard let colorAttachment = renderPassDescriptor.colorAttachments[0] else {
        throw NSError(domain: "DeferredRendererTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to access texture visualization attachment"])
    }
    colorAttachment.texture = outputTexture
    colorAttachment.loadAction = .clear
    colorAttachment.storeAction = .store
    colorAttachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
    else {
        throw NSError(domain: "DeferredRendererTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create texture visualization pass"])
    }

    renderEncoder.setRenderPipelineState(pipeline)
    renderEncoder.setFragmentTexture(texture, index: 0)
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    renderEncoder.endEncoding()

    if readableTextureStorageMode == .managed, let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
        blitEncoder.synchronize(resource: outputTexture)
        blitEncoder.endEncoding()
    }

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    if let error = commandBuffer.error {
        throw error
    }

    return try VisualTestHarness.image(from: outputTexture)
}

private var readableTextureStorageMode: MTLStorageMode {
    #if arch(x86_64)
    return .managed
    #else
    return .shared
    #endif
}

private func visualizeDepthTexture(
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    depthTexture: MTLTexture,
    size: SIMD2<Int>
) throws -> RGBAImage {
    let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut vizVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        const float2 uvs[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };

        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment half4 vizFragment(VertexOut in [[stage_in]], depth2d<float> inputTexture [[texture(0)]]) {
        constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float depth = inputTexture.sample(inputSampler, in.uv);
        float visible = saturate(pow((1.0 - depth) * 24.0, 0.6));
        return half4(half(visible), half(visible), half(visible), 1.0h);
    }
    """

    return try visualizeTexture(device: device, commandQueue: commandQueue, source: source, fragmentName: "vizFragment", texture: depthTexture, size: size)
}

private func visualizeTextureChannel(
    device: MTLDevice,
    commandQueue: MTLCommandQueue,
    texture: MTLTexture,
    size: SIMD2<Int>,
    channel: Int
) throws -> RGBAImage {
    let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut vizVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        const float2 uvs[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };

        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment half4 vizFragment(VertexOut in [[stage_in]], texture2d<float> inputTexture [[texture(0)]]) {
        constexpr sampler inputSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
        float4 value = inputTexture.sample(inputSampler, in.uv);
        float channelValue = value[\(channel)];
        return half4(half(channelValue), half(channelValue), half(channelValue), 1.0h);
    }
    """

    return try visualizeTexture(device: device, commandQueue: commandQueue, source: source, fragmentName: "vizFragment", texture: texture, size: size)
}

private func imageCoverage(_ image: RGBAImage, baseline: [UInt8]) -> ImageCoverage {
    let pixelCount = image.width * image.height
    var changedPixelCount = 0
    var totalDifference = 0

    for pixelIndex in 0..<pixelCount {
        let base = pixelIndex * 4
        var pixelDifference = 0

        for channel in 0..<4 {
            pixelDifference += abs(Int(image.pixels[base + channel]) - Int(baseline[channel]))
        }

        totalDifference += pixelDifference
        if pixelDifference > 4 {
            changedPixelCount += 1
        }
    }

    return ImageCoverage(
        changedPixelCount: changedPixelCount,
        totalPixelCount: pixelCount,
        changedPixelRatio: Double(changedPixelCount) / Double(pixelCount),
        meanNormalizedDifference: Double(totalDifference) / Double(pixelCount * 4 * 255)
    )
}
