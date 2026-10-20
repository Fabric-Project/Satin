@testable import Satin
import Metal
import simd
import XCTest

/// Submissions and records: each `record(scene:)` snapshots the scene as it is at that moment, so
/// changing it between records (as an Iterator does) gives each record its own values and motion;
/// snapshots never cross leases, submissions or command buffers; a submission draws once.
final class SubmissionRecordTests: XCTestCase {
    func testPacketRecordingDoesNotRequireACommandBuffer() throws {
        let arena = FrameArena(device: device)
        let lease = arena.lease(frame: .zero)
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: lease)
        let scene = makeScene()
        scene.mesh.beginOccurrence(frame: .zero)
        let camera = makeCamera()
        let packets = recorder.record(scene.mesh, renderContext: context, pass: .color, materialPass: .all,
                                      views: [RenderView(camera: camera, viewport: [0, 0, 64, 64])])
        XCTAssertEqual(packets.count, 1)
        let before = try modelMatrix(of: storage.packets[packets.lowerBound], in: storage)
        scene.mesh.position = [10, 0, 0]
        scene.mesh.update()
        XCTAssertEqual(try modelMatrix(of: storage.packets[packets.lowerBound], in: storage), before)
    }

    func testPassBindingsKeepTheirBytesAcrossMoreDrawsThanTheOldRing() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let light = PointLight(context: context, color: [1, 0, 0])
        let scene = makeScene()
        scene.root.add(light)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        var snapshots: [(FrameArena.Slice, [UInt8])] = []
        for index in 0 ..< Satin.maxBuffersInFlight + 2 {
            light.color = [Float(index + 1), 0, 0]
            let submission = try makeSubmission(encoder, camera: makeCamera())
            try submission.record(scene: scene.root, renderPassDescriptor: MTLRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
            try submission.seal().encode(into: commandBuffer)
            let slice = try XCTUnwrap(submission.recorder.passBindings.lights)
            snapshots.append((slice, Array(UnsafeRawBufferPointer(start: slice.contents, count: slice.length))))
        }
        for (slice, expected) in snapshots {
            XCTAssertEqual(Array(UnsafeRawBufferPointer(start: slice.contents, count: slice.length)), expected)
        }
        XCTAssertNotEqual(snapshots.first?.1, snapshots.last?.1)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
    }

    func testShadowAndProjectorSnapshotsSurviveLaterDrawsAndRemovedLights() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let light = SpotLight(context: context, color: .one)
        light.castShadow = true
        light.shadow.resolution = (16, 16)
        light.projectionTexture = device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: PhysicalMaterial(context: context))
        mesh.castShadow = true
        mesh.receiveShadow = true
        let root = Object(context: context, label: "Lit", [mesh, light])
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        var snapshots: [(FrameArena.Slice, [UInt8])] = []
        for index in 0 ..< Satin.maxBuffersInFlight + 2 {
            light.position = [Float(index), 2, 3]
            light.shadow.bias = Float(index) * 0.001
            light.projectionTransform.columns.2.x = Float(index) * 0.1
            let submission = try makeSubmission(encoder, camera: makeCamera())
            try submission.record(scene: root, renderPassDescriptor: MTLRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
            try submission.seal().encode(into: commandBuffer)
            let bindings = submission.recorder.passBindings
            for slice in [bindings.shadowData, bindings.shadowMatrices, bindings.projectorMatrices, bindings.projectorTransforms] {
                let slice = try XCTUnwrap(slice)
                snapshots.append((slice, Array(UnsafeRawBufferPointer(start: slice.contents, count: slice.length))))
            }
        }
        let empty = try makeSubmission(encoder, camera: makeCamera())
        try empty.record(scene: Object(context: context), renderPassDescriptor: MTLRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
        try empty.seal().encode(into: commandBuffer)
        XCTAssertNil(empty.recorder.passBindings.lights)
        XCTAssertNil(empty.recorder.passBindings.shadowData)
        XCTAssertNil(empty.recorder.passBindings.projectorMatrices)
        XCTAssertTrue(empty.recorder.passBindings.shadowTextures.isEmpty)
        for (slice, expected) in snapshots {
            XCTAssertEqual(Array(UnsafeRawBufferPointer(start: slice.contents, count: slice.length)), expected)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
    }

    private var device: MTLDevice!
    private var context: Context!
    private var commandQueue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    private struct Scene {
        let root: Object
        let mesh: Mesh
        let material: BasicColorMaterial
    }

    private func makeScene() -> Scene {
        let material = BasicColorMaterial(context: context)
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        let root = Object(context: context, label: "Recorded", [mesh])
        mesh.update()
        return Scene(root: root, mesh: mesh, material: material)
    }

    private func makeCamera(x: Float = 0) -> PerspectiveCamera {
        let camera = PerspectiveCamera(context: context, position: [x, 0, 5], near: 0.1, far: 100, fov: 30)
        camera.aspect = 1
        return camera
    }

    private func makeSubmission(_ encoder: RenderEncoder, frame: FrameTime = .zero, camera: Camera) throws -> SubmissionBuilder {
        encoder.makeSubmissionBuilder(frame: frame, cameras: [camera], viewports: [MTLViewport(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
    }

    /// The buffer and offset a packet binds at `slot` in the vertex stage (vertex uniforms) or
    /// fragment stage (material uniforms).
    private func binding(of packet: DrawPacket, in storage: PacketStorage, vertexSlot: VertexBufferIndex? = nil, fragmentSlot: FragmentBufferIndex? = nil) -> (buffer: MTLBuffer, offset: Int)? {
        for command in storage.commands[Int(packet.commandStart) ..< Int(packet.commandStart + packet.commandCount)] {
            if case let .vertexBuffer(bufferIndex, offset, slot) = command, slot == vertexSlot { return (storage.buffers[Int(bufferIndex)], offset) }
            if case let .perViewVertexBuffer(bufferIndex, offset, slot) = command, slot == vertexSlot { return (storage.buffers[Int(bufferIndex)], offset) }
            if case let .fragmentBuffer(bufferIndex, offset, slot) = command, slot == fragmentSlot { return (storage.buffers[Int(bufferIndex)], offset) }
        }
        return nil
    }

    private func modelMatrix(of packet: DrawPacket, in storage: PacketStorage) throws -> simd_float4x4 {
        let uniforms = try XCTUnwrap(binding(of: packet, in: storage, vertexSlot: .VertexUniforms))
        return (uniforms.buffer.contents() + uniforms.offset).load(as: simd_float4x4.self)
    }

    private func viewMatrix(of packet: DrawPacket, in storage: PacketStorage) throws -> simd_float4x4 {
        let uniforms = try XCTUnwrap(binding(of: packet, in: storage, vertexSlot: .VertexUniforms))
        // viewMatrix follows modelMatrix in VertexUniforms.
        return (uniforms.buffer.contents() + uniforms.offset + MemoryLayout<simd_float4x4>.stride).load(as: simd_float4x4.self)
    }

    private func materialBytes(of packet: DrawPacket, in storage: PacketStorage, size: Int) throws -> [UInt8] {
        let uniforms = try XCTUnwrap(binding(of: packet, in: storage, fragmentSlot: .MaterialUniforms))
        return Array(UnsafeRawBufferPointer(start: uniforms.buffer.contents() + uniforms.offset, count: size))
    }

    private func recordedPackets(_ submission: SubmissionBuilder) -> [DrawPacket] {
        let storage = submission.recorder.storage
        return storage.runs.filter(\.isRecorded).flatMap { storage.packets[$0.packets] }
    }

    // MARK: - Records Snapshot

    func testDrawingRestoresEveryAuxiliaryAttachment() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let descriptor = try makeRenderPassDescriptor()
        var textures: [MTLTexture?] = []
        var resolveTextures: [MTLTexture?] = []
        for index in 1 ... 5 {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
            textureDescriptor.usage = [.renderTarget]
            let texture = index.isMultiple(of: 2) ? nil : try XCTUnwrap(device.makeTexture(descriptor: textureDescriptor))
            let resolveTexture = index.isMultiple(of: 2) ? try XCTUnwrap(device.makeTexture(descriptor: textureDescriptor)) : nil
            textures.append(texture)
            resolveTextures.append(resolveTexture)
            let attachment = try XCTUnwrap(descriptor.colorAttachments[index])
            attachment.texture = texture
            attachment.resolveTexture = resolveTexture
            attachment.loadAction = .load
            attachment.storeAction = .store
            attachment.clearColor = MTLClearColorMake(Double(index) / 10, 0.2, 0.3, 0.4)
        }
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())

        try encoder.draw(frame: .zero, renderPassDescriptor: descriptor, commandBuffer: commandBuffer, scene: Object(context: context), camera: makeCamera())

        for index in 1 ... 5 {
            let attachment = try XCTUnwrap(descriptor.colorAttachments[index])
            XCTAssertTrue(attachment.texture === textures[index - 1])
            XCTAssertTrue(attachment.resolveTexture === resolveTextures[index - 1])
            XCTAssertEqual(attachment.loadAction, .load)
            XCTAssertEqual(attachment.storeAction, .store)
            XCTAssertEqual(attachment.clearColor.red, Double(index) / 10)
            XCTAssertEqual(attachment.clearColor.green, 0.2)
            XCTAssertEqual(attachment.clearColor.blue, 0.3)
            XCTAssertEqual(attachment.clearColor.alpha, 0.4)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
    }

    func testSortingRepeatedRecordsPreservesSceneOrderForEqualRenderOrders() throws {
        let encoder = RenderEncoder(context: context)
        encoder.sortObjects = true
        let scenes = (0 ..< 4).map { _ in makeScene() }
        let orders = [2, 1, 1, 0]
        for (index, scene) in scenes.enumerated() {
            scene.mesh.renderOrder = orders[index]
            scene.mesh.position.x = Float(index) * 0.1
        }
        let root = Object(context: context, label: "Sorted", scenes.map(\.mesh))
        let submission = try makeSubmission(encoder, camera: makeCamera())
        for _ in 0 ..< 2 { try submission.record(scene: root) }

        let positions = try recordedPackets(submission).map {
            try modelMatrix(of: $0, in: submission.recorder.storage).columns.3.x
        }
        let expected: [Float] = [0.3, 0.1, 0.2, 0, 0.3, 0.1, 0.2, 0]
        XCTAssertEqual(positions.count, expected.count)
        for (actual, expected) in zip(positions, expected) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testEachRecordKeepsTheValuesItWasRecordedWith() throws {
        let encoder = RenderEncoder(context: context)
        let scene = makeScene()
        let submission = try makeSubmission(encoder, camera: makeCamera())
        let colors: [simd_float4] = [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1]]

        for (iteration, color) in colors.enumerated() {
            scene.mesh.position = [Float(iteration), 0, 0]
            scene.material.color = color
            scene.mesh.update()
            try submission.record(scene: scene.root)
        }

        let storage = submission.recorder.storage
        let packets = recordedPackets(submission)
        XCTAssertEqual(packets.count, colors.count, "one packet per record")
        let size = scene.material.parameters.size
        var seenBytes: [[UInt8]] = []
        for (iteration, packet) in packets.enumerated() {
            XCTAssertEqual(try modelMatrix(of: packet, in: storage).columns.3.x, Float(iteration), accuracy: 1e-5, "record \(iteration) keeps its position")
            let bytes = try materialBytes(of: packet, in: storage, size: size)
            XCTAssertFalse(seenBytes.contains(bytes), "record \(iteration) keeps its own material values")
            seenBytes.append(bytes)
        }
    }

    func testEachRecordPairsWithTheSameRecordLastFrame() throws {
        let encoder = RenderEncoder(context: context)
        let scene = makeScene()
        let camera = makeCamera()

        func recordFrame(_ frame: FrameTime, positions: [Float]) throws {
            let submission = try makeSubmission(encoder, frame: frame, camera: camera)
            for x in positions {
                scene.mesh.position = [x, 0, 0]
                try submission.record(scene: scene.root)
            }
            // Read before the submission is released.
            if frame.frameNumber == 1 {
                XCTAssertEqual(scene.mesh.occurrence.previousModelMatrix.columns.3.x, 10, accuracy: 1e-5, "the second record pairs with last frame's second")
            }
        }

        try recordFrame(.zero, positions: [0, 10])
        try recordFrame(FrameTime.zero.next(time: 1.0 / 60.0), positions: [1, 11])
    }

    func testCameraChangesAfterMakingASubmissionDontReachItsRecords() throws {
        let encoder = RenderEncoder(context: context)
        let scene = makeScene()
        let camera = makeCamera(x: 0)
        let submission = try makeSubmission(encoder, camera: camera)
        let viewAtCreation = camera.viewMatrix

        camera.position = [3, 0, 5]
        camera.update()
        try submission.record(scene: scene.root)

        let packet = try XCTUnwrap(recordedPackets(submission).first)
        XCTAssertEqual(try viewMatrix(of: packet, in: submission.recorder.storage), viewAtCreation)
    }

    // MARK: - Leases

    func testTwoOutstandingSubmissionsSharingAMaterialEachBindTheirOwnSnapshot() throws {
        let encoder = RenderEncoder(context: context)
        let scene = makeScene()
        let camera = makeCamera()
        let size = scene.material.parameters.size
        let first = try makeSubmission(encoder, camera: camera)
        let second = try makeSubmission(encoder, camera: camera)

        scene.material.color = [1, 0, 0, 1]
        try first.record(scene: scene.root)
        // Unchanged, then changed: neither may reuse the first submission's slice.
        try second.record(scene: scene.root)
        scene.material.color = [0, 1, 0, 1]
        try second.record(scene: scene.root)

        let firstPacket = try XCTUnwrap(recordedPackets(first).first)
        let secondPackets = recordedPackets(second)
        XCTAssertEqual(secondPackets.count, 2)
        let firstBinding = try XCTUnwrap(binding(of: firstPacket, in: first.recorder.storage, fragmentSlot: .MaterialUniforms))
        let unchangedBinding = try XCTUnwrap(binding(of: secondPackets[0], in: second.recorder.storage, fragmentSlot: .MaterialUniforms))
        XCTAssertFalse(firstBinding.buffer === unchangedBinding.buffer && firstBinding.offset == unchangedBinding.offset, "another lease takes its own snapshot")
        XCTAssertNotEqual(try materialBytes(of: firstPacket, in: first.recorder.storage, size: size),
                          try materialBytes(of: secondPackets[1], in: second.recorder.storage, size: size), "each binds its own values")
    }

    func testAPaletteSnapshotsOncePerRecordAndPairsByOrdinal() throws {
        let palette = JointPalette(jointCount: 1)
        let encoder = RenderEncoder(context: context)
        let camera = makeCamera()

        let frame0 = try makeSubmission(encoder, camera: camera)
        palette.update(matrices: [simd_float4x4(translation: [1, 0, 0])])
        frame0.recorder.beginRecord()
        let shared = palette.snapshot(recorder: frame0.recorder)
        let again = palette.snapshot(recorder: frame0.recorder)
        XCTAssertTrue(shared.buffer === again.buffer && shared.offset == again.offset, "meshes sharing a palette in one record bind one snapshot")
        frame0.recorder.beginRecord()
        palette.update(matrices: [simd_float4x4(translation: [5, 0, 0])])
        _ = palette.snapshot(recorder: frame0.recorder)

        let frame1 = try makeSubmission(encoder, frame: FrameTime.zero.next(time: 1.0 / 60.0), camera: camera)
        frame1.recorder.beginRecord()
        palette.update(matrices: [simd_float4x4(translation: [2, 0, 0])])
        let first = palette.snapshot(recorder: frame1.recorder)
        let joint = (first.buffer.contents() + first.offset).load(as: SkinJoint.self)
        XCTAssertEqual(joint.previous.columns.3.x, 1, accuracy: 1e-5, "the first record pairs with last frame's first, not its last")
    }

    func testInstanceMotionPairsByRecordAndAResizeStartsStill() throws {
        let encoder = RenderEncoder(context: context)
        let camera = makeCamera()
        let instances = InstancedMesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context), count: 2)
        let root = Object(context: context, label: "Instances", [instances])

        func recordFrame(_ frame: FrameTime, positions: [Float]) throws -> [InstanceMatrixUniforms] {
            instances.setInstanceMatrices(positions.map { simd_float4x4(translation: [$0, 0, 0]) })
            instances.update()
            let submission = try makeSubmission(encoder, frame: frame, camera: camera)
            try submission.record(scene: root)
            let storage = submission.recorder.storage
            let packet = try XCTUnwrap(recordedPackets(submission).first)
            let slice = try XCTUnwrap(binding(of: packet, in: storage, vertexSlot: .InstanceMatrixUniforms))
            let pointer = (slice.buffer.contents() + slice.offset).bindMemory(to: InstanceMatrixUniforms.self, capacity: positions.count)
            return Array(UnsafeBufferPointer(start: pointer, count: positions.count))
        }

        let frame0 = FrameTime.zero
        let frame1 = frame0.next(time: 1.0 / 60.0)
        let frame2 = frame1.next(time: 2.0 / 60.0)

        let first = try recordFrame(frame0, positions: [0, 10])
        XCTAssertEqual(first[1].previousModelMatrix, first[1].modelMatrix, "a first frame has no motion")

        let second = try recordFrame(frame1, positions: [1, 11])
        XCTAssertEqual(second[0].previousModelMatrix.columns.3.x, 0, accuracy: 1e-5)
        XCTAssertEqual(second[1].previousModelMatrix.columns.3.x, 10, accuracy: 1e-5, "each instance pairs with itself last frame")

        let resized = try recordFrame(frame2, positions: [2, 12, 20])
        for instance in resized {
            XCTAssertEqual(instance.previousModelMatrix, instance.modelMatrix, "a new instance count starts every instance still")
        }
    }

    // MARK: - Lifetime

    func testADrawnSubmissionIsConsumedAndReturnsItsStorage() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let scene = makeScene()
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        try submission.record(scene: scene.root)
        let available = encoder.packetStoragePool.availableCount

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = target
        try submission.record(scene: Object(context: context), renderPassDescriptor: renderPassDescriptor, preparationCommandBuffer: commandBuffer)
        try submission.seal().encode(into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertNil(commandBuffer.error)
        XCTAssertTrue(submission.isConsumed)
        XCTAssertEqual(encoder.packetStoragePool.availableCount, available + 1, "the lease is returned once")
        XCTAssertTrue(submission.recorder.storage.packets.isEmpty, "and cleared")
    }

    func testASubmissionReleasedWithoutDrawingReturnsItsStorage() throws {
        let encoder = RenderEncoder(context: context)
        let available = encoder.packetStoragePool.availableCount
        do {
            let submission = try makeSubmission(encoder, camera: makeCamera())
            try submission.record(scene: makeScene().root)
        }
        XCTAssertEqual(encoder.packetStoragePool.availableCount, available + 1)
    }

    // MARK: - Contract

    private func makeRenderPassDescriptor(pixelFormat: MTLPixelFormat = .bgra8Unorm, storageMode: MTLStorageMode = .private) throws -> MTLRenderPassDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: 64, height: 64, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = storageMode
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        return renderPassDescriptor
    }

    /// Commits `commandBuffer` and waits until its completed handlers, the arena's included, have run.
    private func complete(_ commandBuffer: MTLCommandBuffer) {
        let handlersRan = expectation(description: "completed handlers ran")
        commandBuffer.addCompletedHandler { _ in handlersRan.fulfill() }
        commandBuffer.commit()
        wait(for: [handlersRan], timeout: 5)
    }

    func testChangingTheEncoderAfterMakingASubmissionDoesntReachIt() throws {
        let encoder = RenderEncoder(context: context)
        encoder.sortObjects = true
        encoder.clearColor = MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1)
        let submission = try makeSubmission(encoder, camera: makeCamera())

        encoder.sortObjects = false
        encoder.clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)

        XCTAssertTrue(submission.configuration.sortObjects)
        XCTAssertEqual(submission.configuration.clearColor.blue, 1)
        XCTAssertEqual(submission.configuration.clearColor.red, 0)
        XCTAssertFalse(encoder.sortObjects, "the encoder keeps its new settings for later submissions")
    }

    func testAChangeToTheEncoderDuringADrawAffectsOnlyLaterSubmissions() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        encoder.clearColor = MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())

        let changer = EncoderChangingObject(context: context, encoder: encoder, clearColor: MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1))
        try submission.record(scene: changer, renderPassDescriptor: makeRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
        try submission.seal().encode(into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertEqual(changer.clearColorDuringDraw?.blue, 1, "the draw reads its submission's settings")
        XCTAssertEqual(changer.clearColorDuringDraw?.red, 0)
        XCTAssertEqual(encoder.clearColor.red, 1, "the change lands for later submissions")
        XCTAssertEqual(try makeSubmission(encoder, camera: makeCamera()).configuration.clearColor.red, 1)
    }

    func testAMismatchedColorFormatIsRejectedBeforeAnyWork() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        try submission.record(scene: makeScene().root)
        let recordedPacketCount = submission.recorder.storage.packets.count
        let available = encoder.packetStoragePool.availableCount

        XCTAssertThrowsError(try submission.record(scene: makeScene().root, renderPassDescriptor: makeRenderPassDescriptor(pixelFormat: .rgba16Float), preparationCommandBuffer: commandBuffer)) { error in
            XCTAssertEqual(error as? SubmissionError, .destinationMismatch(attachment: "color", expected: .bgra8Unorm, found: .rgba16Float))
        }
        XCTAssertFalse(submission.isConsumed, "a rejected submission stays usable")
        XCTAssertEqual(submission.recorder.storage.packets.count, recordedPacketCount, "and nothing was updated or recorded")
        XCTAssertEqual(encoder.packetStoragePool.availableCount, available, "nor its lease returned")

        try submission.record(scene: Object(context: context), renderPassDescriptor: makeRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
        try submission.seal().encode(into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)
        XCTAssertTrue(submission.isConsumed, "it draws with a matching descriptor")
    }

    func testAMismatchedRenderTargetLeavesTheDescriptorAsItWas() throws {
        for sampleCount in [1, 4] {
            let context = Context(device: device, sampleCount: sampleCount, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
            let encoder = RenderEncoder(context: context)
            encoder.resize((width: 64, height: 64))
            let wrongTarget = try XCTUnwrap(makeRenderPassDescriptor(pixelFormat: .rgba16Float).colorAttachments[0].texture)
            let camera = makeCamera()
            let viewport = MTLViewport(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)

            let draws: [(MTLRenderPassDescriptor, MTLCommandBuffer) throws -> Void] = [
                { try encoder.draw(frame: .zero, renderPassDescriptor: $0, commandBuffer: $1, scene: Object(context: context), camera: camera, renderTarget: wrongTarget) },
                { try encoder.draw(frame: .zero, renderPassDescriptor: $0, commandBuffer: $1, scene: Object(context: context), cameras: [camera], viewports: [viewport], renderTarget: wrongTarget) },
            ]
            for (overload, draw) in draws.enumerated() {
                let renderPassDescriptor = try makeRenderPassDescriptor()
                let originalTexture = renderPassDescriptor.colorAttachments[0].texture
                let originalResolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
                let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())

                XCTAssertThrowsError(try draw(renderPassDescriptor, commandBuffer)) { error in
                    guard case .destinationMismatch = error as? SubmissionError else {
                        return XCTFail("expected a destination mismatch, got \(error)")
                    }
                }
                XCTAssertTrue(renderPassDescriptor.colorAttachments[0].texture === originalTexture, "overload \(overload), \(sampleCount)x: the texture is restored")
                XCTAssertTrue(renderPassDescriptor.colorAttachments[0].resolveTexture === originalResolveTexture, "overload \(overload), \(sampleCount)x: the resolve texture is restored")
            }
        }
    }

    func testASealedBuilderRejectsASecondSealAndAnotherRecord() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        try submission.record(scene: Object(context: context), renderPassDescriptor: makeRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)

        try submission.seal().encode(into: commandBuffer)

        XCTAssertThrowsError(try submission.seal()) { error in
            XCTAssertEqual(error as? SubmissionError, .alreadyDrawn)
        }
        XCTAssertThrowsError(try submission.record(scene: Object(context: context), renderPassDescriptor: makeRenderPassDescriptor())) { error in
            XCTAssertEqual(error as? SubmissionError, .alreadyDrawn)
        }
        XCTAssertThrowsError(try submission.record(scene: makeScene().root)) { error in
            XCTAssertEqual(error as? SubmissionError, .alreadyDrawn)
        }
    }

    func testSubmissionsKeepTheirOwnRecordsWhateverOrderTheyAreRecordedIn() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let material = BasicColorMaterial(context: context)
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        let root = Object(context: context, label: "Ordered", [mesh])
        mesh.update()

        let first = try makeSubmission(encoder, camera: makeCamera())
        let second = try makeSubmission(encoder, camera: makeCamera())
        material.color = [2, 0, 0, 1]
        try second.record(scene: root)
        material.color = [1, 0, 0, 1]
        try first.record(scene: root)

        try first.record(scene: Object(context: context), renderPassDescriptor: makeRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
        try first.seal().encode(into: commandBuffer)
        try second.record(scene: Object(context: context), renderPassDescriptor: makeRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
        try second.seal().encode(into: commandBuffer)
        let firstRecorded = recordedColorRed(in: first.recorder.storage)
        let secondRecorded = recordedColorRed(in: second.recorder.storage)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertNil(commandBuffer.error)
        XCTAssertEqual(firstRecorded, [1], "each submission draws what was recorded into it")
        XCTAssertEqual(secondRecorded, [2])
    }
}

/// Changes the encoder's clear colour while the encoder draws it, as a callback might, and keeps
/// what the encoder reported in the middle of that draw.
private final class EncoderChangingObject: Object {
    private let encoder: RenderEncoder
    private let newClearColor: MTLClearColor
    private(set) var clearColorDuringDraw: MTLClearColor?

    init(context: Context, encoder: RenderEncoder, clearColor: MTLClearColor) {
        self.encoder = encoder
        newClearColor = clearColor
        super.init(context: context, label: "Encoder Changing")
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    override func encode(in context: EncodingContext) {
        encoder.clearColor = newClearColor
        clearColorDuringDraw = encoder.clearColor
        super.encode(in: context)
    }
}
