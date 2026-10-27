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

    func testSharedMaterialLightingMatchesIsolatedDrawsInBothRecordingOrders() throws {
        // Different target-wide light counts, and the same light set with and without shadows.
        // Compare pixels, rather than only checking that packet tables contain different counts.
        let configurations = [(lights: 0, shadows: false), (lights: 1, shadows: false),
                              (lights: 2, shadows: false), (lights: 2, shadows: true)]
        for mode in [RenderingMode.forward, .forwardPlus, .deferredGeometry] {
            let references = try configurations.map { configuration -> [UInt8] in
                let renderer = RenderEncoder(context: context)
                renderer.renderingMode = mode
                let material = BasicDiffuseMaterial(context: context)
                return try renderLighting(configuration, renderer: renderer, material: material)
            }
            XCTAssertNotEqual(references[0], references[1], "Unlit and lit controls must differ in \(mode)")
            XCTAssertNotEqual(references[1], references[2], "The additional blue light must affect the image in \(mode)")

            XCTAssertNotEqual(references[2], references[3], "Shadows must affect visible receiver pixels in \(mode)")

            for order in [[0, 1, 2, 3], [3, 2, 1, 0]] {
                let renderer = RenderEncoder(context: context)
                renderer.renderingMode = mode
                let material = BasicDiffuseMaterial(context: context)
                var submissions: [(index: Int, sealed: SealedSubmission, target: MTLTexture)] = []
                for index in order {
                    let output = try target()
                    let sealed = try recordLighting(configurations[index], renderer: renderer, material: material, output: output)
                    submissions.append((index, sealed, output))
                }
                // Replay in the opposite order, after all recordings changed the shared shader.
                let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
                for submission in submissions.reversed() {
                    try submission.sealed.encode(into: commandBuffer)
                }
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                XCTAssertEqual(commandBuffer.status, .completed, String(describing: commandBuffer.error))
                for submission in submissions {
                    let actual = bytes(submission.target)
                    let expected = references[submission.index]
                    let differentBytes = zip(actual, expected).filter { $0 != $1 }.count
                    XCTAssertEqual(differentBytes, 0,
                                   "Shared material, \(mode), recording order \(order), configuration \(submission.index)")
                }
            }
        }
    }

    private func renderLighting(_ configuration: (lights: Int, shadows: Bool), renderer: RenderEncoder,
                                material: Material) throws -> [UInt8] {
        let output = try target()
        let submission = try recordLighting(configuration, renderer: renderer, material: material, output: output)
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try submission.encode(into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed, String(describing: commandBuffer.error))
        return bytes(output)
    }

    private func recordLighting(_ configuration: (lights: Int, shadows: Bool), renderer: RenderEncoder,
                                material: Material, output: MTLTexture) throws -> SealedSubmission {
        renderer.resize((32, 32))
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        mesh.castShadow = true
        mesh.receiveShadow = true
        let receiver = Mesh(context: context, geometry: QuadGeometry(context: context, size: 3), material: material)
        receiver.position.z = -1
        receiver.receiveShadow = true
        let scene = Object(context: context, label: "Lighting isolation", [receiver, mesh])
        for index in 0 ..< configuration.lights {
            let light = DirectionalLight(context: context, color: index == 0 ? [1, 0, 0] : [0, 0, 1])
            light.position = [2, 1, 5]
            light.lookAt(target: .zero)
            light.castShadow = configuration.shadows && index == 0
            light.shadow.resolution = (32, 32)
            scene.add(light)
        }
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let viewport = MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = output
        let builder = renderer.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport])
        mesh.update()
        receiver.update()
        // This is the Iterator path: capture children first, finalize against the target afterwards.
        try builder.record(scene: scene)
        try builder.record(scene: Object(context: context), renderPassDescriptor: descriptor)
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

    func testExternalBytesCopiedOnRecordSurviveAnOverwriteBeforeEncoding() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let external = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared))
        external.contents().storeBytes(of: simd_float4(1, 0, 0, 1), as: simd_float4.self)
        let externalMaterial = ExternalColorMaterial(context: context)
        externalMaterial.colors = external
        let referenceMaterial = BasicColorMaterial(context: context)
        referenceMaterial.set("Color", simd_float4(1, 0, 0, 1))
        let externalMesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: externalMaterial)
        let referenceMesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: referenceMaterial)
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let viewport = MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)
        let externalTarget = try target()
        let referenceTarget = try target()
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = externalTarget
        let sealed = try seal(encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport]),
                              descriptor: descriptor, scene: Object(context: context, label: "External", [externalMesh]))
        descriptor.colorAttachments[0].texture = referenceTarget
        let reference = try seal(encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport]),
                                 descriptor: descriptor, scene: Object(context: context, label: "Reference", [referenceMesh]))

        // Overwritten after sealing, before anything is encoded: the recording copied its bytes.
        external.contents().storeBytes(of: simd_float4(0, 0, 1, 1), as: simd_float4.self)
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try sealed.encode(into: commandBuffer)
        try reference.encode(into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertEqual(bytes(externalTarget), bytes(referenceTarget), "the box draws red, the colour when it was recorded")
    }

    /// Renders `scene` sealed into its own target and returns it, encoded later by the caller.
    private func sealColor(_ encoder: RenderEncoder, scene: Object, camera: Camera) throws -> (sealed: SealedSubmission, target: MTLTexture) {
        let viewport = MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)
        let target = try target()
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        let sealed = try seal(encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport]), descriptor: descriptor, scene: scene)
        return (sealed, target)
    }

    private func encodeAndWait(_ sealed: [SealedSubmission]) throws {
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        for submission in sealed { try submission.encode(into: commandBuffer) }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
    }

    func testUniformsWrittenAtEncodeUseTheTransformsRecordedAtSeal() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
        let scene = Object(context: context, label: "Scene", [mesh])
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let viewport = MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = try target()
        let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [viewport])
        let sealed = try seal(builder, descriptor: descriptor, scene: scene)
        let recordedModel = mesh.worldMatrix
        let recordedView = camera.viewMatrix
        let storage = builder.recorder.storage
        XCTAssertFalse(storage.vertexUniformsJobs.isEmpty, "the write waits for encoding")

        mesh.position = [3, 0, 0]
        mesh.update()
        camera.position = [0, 4, 5]
        camera.update()
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try sealed.encode(into: commandBuffer)

        XCTAssertTrue(storage.vertexUniformsJobs.isEmpty, "encoding wrote them")
        var found = false
        for packet in storage.packets {
            for command in storage.commands[Int(packet.commandStart) ..< Int(packet.commandStart + packet.commandCount)] {
                guard case let .perViewVertexBuffer(bufferIndex, offset, .VertexUniforms) = command else { continue }
                let uniforms = (storage.buffers[Int(bufferIndex)].contents() + offset).load(as: VertexUniforms.self)
                if uniforms.modelMatrix == recordedModel {
                    XCTAssertEqual(uniforms.viewMatrix, recordedView, "the view as sealed, not as moved")
                    found = true
                }
            }
        }
        XCTAssertTrue(found, "the mesh's uniforms hold its transform as sealed, not as moved")
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func testObjectsRemovedAndReleasedAfterSealingStillDrawInWhatWasSealed() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let scene = Object(context: context, label: "Scene")
        do {
            let material = BasicColorMaterial(context: context)
            material.set("Color", simd_float4(1, 0, 0, 1))
            scene.add(Mesh(context: context, geometry: BoxGeometry(context: context), material: material))
        }
        let (sealed, removedTarget) = try sealColor(encoder, scene: scene, camera: camera)

        // B removes the mesh; nothing else holds it, its material or its geometry.
        scene.removeAll()
        let (afterRemoval, emptyTarget) = try sealColor(encoder, scene: scene, camera: camera)

        let referenceMaterial = BasicColorMaterial(context: context)
        referenceMaterial.set("Color", simd_float4(1, 0, 0, 1))
        let reference = Object(context: context, label: "Reference", [Mesh(context: context, geometry: BoxGeometry(context: context), material: referenceMaterial)])
        let (referenceSealed, referenceTarget) = try sealColor(encoder, scene: reference, camera: camera)

        try encodeAndWait([afterRemoval, sealed, referenceSealed])
        XCTAssertEqual(bytes(removedTarget), bytes(referenceTarget), "A draws the box it sealed")
        XCTAssertNotEqual(bytes(emptyTarget), bytes(referenceTarget), "B draws without it")
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
            items.append((texture, try encoder.seal(frame: .zero, renderPassDescriptor: descriptor, mesh: mesh, cameras: [camera], viewports: [viewport])))
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

    func testAbandonedSealedWorkReturnsItsStorageWithoutEncoding() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let camera = PerspectiveCamera(context: context)
        let before = encoder.packetStoragePool.availableCount
        try autoreleasepool {
            let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [])
            let sealed = try seal(builder, descriptor: MTLRenderPassDescriptor(), scene: Object(context: context))
            withExtendedLifetime(sealed) {}
        }
        XCTAssertEqual(encoder.packetStoragePool.availableCount, before + 1)
    }

    // MARK: - Static shadows: recorded state is reusable only after successful encoding

    private func staticShadowScene() -> (scene: Object, light: SpotLight) {
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: PhysicalMaterial(context: context))
        mesh.castShadow = true
        mesh.receiveShadow = true
        let light = SpotLight(context: context, color: .one)
        light.castShadow = true
        light.shadow.autoUpdate = false
        light.shadow.resolution = (16, 16)
        return (Object(context: context, label: "Static shadow", [mesh, light]), light)
    }

    func testAStaticShadowIsReusableOnlyOnceItsPassesAreEncoded() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let (scene, light) = staticShadowScene()
        XCTAssertTrue(light.shadow.shouldRender)

        let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [PerspectiveCamera(context: context)], viewports: [])
        let sealed = try seal(builder, descriptor: MTLRenderPassDescriptor(), scene: scene)

        XCTAssertFalse(light.shadow.needsUpdate, "the producer captured the current light revision")
        XCTAssertTrue(light.shadow.shouldRender, "another submission must not reuse a map whose producer has not encoded")

        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try sealed.encode(into: commandBuffer)
        XCTAssertFalse(light.shadow.shouldRender, "the map's producer is encoded and can precede its readers on the same queue")
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed, String(describing: commandBuffer.error))
    }

    func testAbandoningASealedSubmissionMarksItsShadowsDirtyAgain() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((32, 32))
        let (scene, light) = staticShadowScene()
        let builder = encoder.makeSubmissionBuilder(frame: .zero, cameras: [PerspectiveCamera(context: context)], viewports: [])
        let sealed = try seal(builder, descriptor: MTLRenderPassDescriptor(), scene: scene)

        encoder.abandon(sealed)

        XCTAssertTrue(light.shadow.shouldRender, "its passes will never run, so the next frame renders the map")
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertThrowsError(try sealed.encode(into: commandBuffer), "an abandoned submission can't be encoded") { error in
            XCTAssertEqual(error as? SubmissionError, .alreadyDrawn)
        }
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
}

/// BasicColor whose material uniforms come from a caller-owned buffer, copied when recorded.
final class ExternalColorMaterial: BasicColorMaterial {
    // The shader is found by class name: draw with BasicColor's.
    override var prefix: String { "BasicColor" }

    var colors: MTLBuffer?

    override func draw(in context: MaterialDrawContext) throws {
        try super.draw(in: context)
        if let colors { try context.setFragmentBuffer(colors, index: .MaterialUniforms, copyOnRecordLength: colors.length) }
    }
}
