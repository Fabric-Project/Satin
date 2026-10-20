@testable import Satin
import Metal
import simd
import XCTest

final class SealedSubmissionTests: XCTestCase {
    private var context: Context!
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func target() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 32, height: 32, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    private func bytes(_ texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 32 * 32 * 4)
        texture.getBytes(&result, bytesPerRow: 32 * 4, from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
        return result
    }

    private func seal(_ builder: SubmissionBuilder, descriptor: MTLRenderPassDescriptor, scene: Object) throws -> SealedSubmission {
        try builder.record(scene: scene, renderPassDescriptor: descriptor)
        return try builder.seal()
    }

    func testSealAMutateAndSealBThenEncodeAWithoutLiveReads() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let material = BasicColorMaterial(context: context)
        material.set("Color", simd_float4(1, 0, 0, 1))
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        let scene = Object(context: context, label: "Scene", [mesh])
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let viewport = MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)
        let firstTarget = try target()
        let referenceTarget = try target()
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = firstTarget
        let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport])
        try builder.record(scene: scene, renderPassDescriptor: descriptor)
        let referenceBuilder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport])
        descriptor.colorAttachments[0].texture = referenceTarget
        let reference = try seal(referenceBuilder, descriptor: descriptor, scene: scene)

        material.set("Color", simd_float4(0, 0, 1, 1))
        mesh.position = [1, 0, 0]
        mesh.geometry = SphereGeometry(context: context)
        camera.position = [2, 0, 5]
        encoder.clearColor = MTLClearColorMake(0, 1, 0, 1)
        let secondTarget = try target()
        descriptor.colorAttachments[0].texture = secondTarget
        let second = try seal(encoder.makeSubmissionBuilder(frame: .zero.next(time: 1), cameras: [camera], viewports: [viewport]), descriptor: descriptor, scene: scene)
        // Sealing must not recapture the now-mutated scene or the caller's descriptor.
        let sealed = try builder.seal()
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try second.encode(into: commandBuffer)
        try reference.encode(into: commandBuffer)
        try sealed.encode(into: commandBuffer)
        XCTAssertThrowsError(try sealed.encode(into: commandBuffer))
        XCTAssertThrowsError(try builder.record(scene: scene, renderPassDescriptor: descriptor))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertEqual(bytes(firstTarget), bytes(referenceTarget))
        XCTAssertNotEqual(bytes(firstTarget), bytes(secondTarget))
    }

    func testShadowPassesAndDeferredResolveStayFrozen() throws {
        for lightKind in 0 ..< 3 {
            let encoder = RenderEncoder(context: context)
            encoder.renderingMode = .deferredGeometry
            encoder.resize((32, 32))
            let material = PhysicalMaterial(context: context)
            material.set("Base Color", simd_float4(0.8, 0.3, 0.2, 1))
            let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
            mesh.castShadow = true
            mesh.receiveShadow = true
            let light: Light
            switch lightKind {
                case 0: light = PointLight(context: context, color: .one, intensity: 10)
                case 1: light = SpotLight(context: context, color: .one, intensity: 10)
                default: light = DirectionalLight(context: context, color: .one, intensity: 2)
            }
            light.position = [2, 3, 4]
            light.lookAt(target: .zero)
            light.castShadow = true
            light.shadow.resolution = (32, 32)
            let scene = Object(context: context, label: "Lit", [mesh, light])
            let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
            let viewport = MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)
            let firstTarget = try target()
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = firstTarget
            let sealed = try seal(encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport]), descriptor: descriptor, scene: scene)
            // A reference encoded before mutation also detects shared output/route state.
            let referenceTarget = try target()
            descriptor.colorAttachments[0].texture = referenceTarget
            let reference = try seal(encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport]), descriptor: descriptor, scene: scene)
            let baselineBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            try reference.encode(into: baselineBuffer)
            baselineBuffer.commit()
            baselineBuffer.waitUntilCompleted()
            let expected = bytes(referenceTarget)
            XCTAssertTrue(expected.enumerated().contains { $0.offset % 4 != 3 && $0.element > 0 }, "the reference draws lit pixels")
            light.color = [0, 0, 1]
            light.position = [-3, 1, 0]
            light.shadow.resolution = (64, 64)
            camera.position = [2, 1, 5]
            mesh.position = [0.5, 0, 0]
            let secondTarget = try target()
            descriptor.colorAttachments[0].texture = secondTarget
            let second = try seal(encoder.makeSubmissionBuilder(frame: .zero.next(time: 1), cameras: [camera], viewports: [viewport]), descriptor: descriptor, scene: scene)
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            try second.encode(into: commandBuffer)
            try sealed.encode(into: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            XCTAssertEqual(commandBuffer.status, .completed)
            XCTAssertEqual(bytes(firstTarget), expected, "shadow kind \(lightKind)")
            XCTAssertNotEqual(bytes(secondTarget), expected)
        }
    }

    func testPostprocessTargetsAndRecordedColorsRemainDistinct() throws {
        let encoder = PostProcessRenderEncoder(context: context)
        encoder.resize((32, 32))
        let material = BasicColorMaterial(context: context)
        let mesh = Mesh(context: context, geometry: QuadGeometry(context: context), material: material)
        let camera = OrthographicCamera(context: context)
        let viewport = MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)
        let descriptor = MTLRenderPassDescriptor()
        var items: [(MTLTexture, SealedSubmission)] = []
        for red: Float in [0.2, 0.4, 0.6] {
            material.set("Color", simd_float4(red, 0, 0, 1))
            let texture = try target()
            descriptor.colorAttachments[0].texture = texture
            items.append((texture, encoder.seal(frame: .zero, renderPassDescriptor: descriptor, mesh: mesh, cameras: [camera], viewports: [viewport])))
        }
        material.set("Color", simd_float4(0, 1, 0, 1))
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        for (_, sealed) in items { try sealed.encode(into: commandBuffer) }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        let images = items.map { bytes($0.0) }
        XCTAssertNotEqual(images[0], images[1])
        XCTAssertNotEqual(images[1], images[2])
    }

    func testConsumedAliasesDoNotKeepCompletionOwnersAlive() throws {
        final class Owner {}
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [])
        weak var owner: Owner?
        do {
            let value = Owner()
            owner = value
            builder.retainUntilCompleted(value)
        }
        let sealed = try seal(builder, descriptor: MTLRenderPassDescriptor(), scene: Object(context: context))
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try sealed.encode(into: commandBuffer)
        XCTAssertNotNil(owner)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(owner)
        withExtendedLifetime((builder, sealed)) {}
    }

    func testAbandonedSealedWorkReleasesOwnersWithBuilderAliasAlive() throws {
        final class Owner {}
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let camera = PerspectiveCamera(context: context)
        let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [])
        weak var owner: Owner?
        do {
            let value = Owner()
            owner = value
            builder.retainUntilCompleted(value)
        }
        var sealed: SealedSubmission? = try seal(builder, descriptor: MTLRenderPassDescriptor(), scene: Object(context: context))
        XCTAssertNotNil(owner)
        withExtendedLifetime(sealed) {}
        sealed = nil
        XCTAssertNil(owner)
        withExtendedLifetime(builder) {}
    }

    func testAbandonedRecordingDoesNotMarkAnUnrenderedStaticShadowClean() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: PhysicalMaterial(context: context))
        mesh.castShadow = true
        mesh.receiveShadow = true
        let light = SpotLight(context: context, color: .one)
        light.castShadow = true
        light.shadow.autoUpdate = false
        light.shadow.resolution = (16, 16)
        let scene = Object(context: context, label: "Unsubmitted", [mesh, light])
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        do {
            let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [])
            let sealed = try seal(builder, descriptor: MTLRenderPassDescriptor(), scene: scene)
            withExtendedLifetime(sealed) {}
        }
        XCTAssertTrue(light.shadow.shouldRender, "No GPU work was submitted, so the map is still dirty")
    }

    func testEncodedButUncommittedWorkReturnsItsPacketStorage() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let before = encoder.packetStoragePool.availableCount
        try autoreleasepool {
            let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [])
            let sealed = try seal(builder, descriptor: MTLRenderPassDescriptor(), scene: Object(context: context))
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            try sealed.encode(into: commandBuffer)
        }
        XCTAssertEqual(encoder.packetStoragePool.availableCount, before + 1)
    }

    func testOldShadowCompletionCannotCleanANewerDirtyGeneration() {
        let light = SpotLight(context: context, color: .one)
        let shadow = light.shadow
        shadow.autoUpdate = false
        let first = shadow.recordingCompletion()
        XCTAssertTrue(first === shadow.recordingCompletion(), "pending recordings of one generation share completion")
        shadow.needsUpdate = true
        let second = shadow.recordingCompletion()
        first.complete(succeeded: true)
        XCTAssertTrue(shadow.needsUpdate)
        second.complete(succeeded: false)
        XCTAssertTrue(shadow.needsUpdate)
        second.complete(succeeded: true)
        XCTAssertFalse(shadow.needsUpdate)
    }
}
