@testable import Satin
import Metal
import simd
import XCTest

/// Submissions and records: each `record(scene:)` snapshots the scene as it is at that moment, so
/// changing it between records (as an Iterator does) gives each record its own values and motion;
/// snapshots never cross leases, submissions or command buffers; a submission draws once.
final class SubmissionRecordTests: XCTestCase {
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

    private func makeSubmission(_ encoder: RenderEncoder, frame: FrameTime = .zero, camera: Camera, commandBuffer: MTLCommandBuffer? = nil) throws -> RenderSubmission {
        let commandBuffer = try commandBuffer ?? XCTUnwrap(commandQueue.makeCommandBuffer())
        return encoder.makeSubmission(frame: frame, commandBuffer: commandBuffer, cameras: [camera], viewports: [MTLViewport(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
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

    private func recordedPackets(_ submission: RenderSubmission) -> [DrawPacket] {
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
        let sharedCommandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())

        for secondCommandBuffer in [sharedCommandBuffer, try XCTUnwrap(commandQueue.makeCommandBuffer())] {
            let first = try makeSubmission(encoder, camera: camera, commandBuffer: sharedCommandBuffer)
            let second = try makeSubmission(encoder, camera: camera, commandBuffer: secondCommandBuffer)

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
        let submission = try makeSubmission(encoder, camera: makeCamera(), commandBuffer: commandBuffer)
        try submission.record(scene: scene.root)
        let available = encoder.packetStoragePool.availableCount

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = target
        try encoder.draw(submission: submission, renderPassDescriptor: renderPassDescriptor, scene: Object(context: context))
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
        let submission = try makeSubmission(encoder, camera: makeCamera(), commandBuffer: commandBuffer)

        let changer = EncoderChangingObject(context: context, encoder: encoder, clearColor: MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1))
        try encoder.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(), scene: changer)
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
        let submission = try makeSubmission(encoder, camera: makeCamera(), commandBuffer: commandBuffer)
        try submission.record(scene: makeScene().root)
        let recordedPacketCount = submission.recorder.storage.packets.count
        let available = encoder.packetStoragePool.availableCount

        XCTAssertThrowsError(try encoder.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(pixelFormat: .rgba16Float), scene: makeScene().root)) { error in
            XCTAssertEqual(error as? RenderSubmission.Error, .destinationMismatch(attachment: "color", expected: .bgra8Unorm, found: .rgba16Float))
        }
        XCTAssertFalse(submission.isConsumed, "a rejected submission stays usable")
        XCTAssertEqual(submission.recorder.storage.packets.count, recordedPacketCount, "and nothing was updated or recorded")
        XCTAssertEqual(encoder.packetStoragePool.availableCount, available, "nor its lease returned")

        try encoder.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)
        XCTAssertTrue(submission.isConsumed, "it draws with a matching descriptor")
    }

    func testAnotherEncodersSubmissionIsRejectedBeforeAnyWork() throws {
        let owner = RenderEncoder(context: context)
        owner.resize((width: 64, height: 64))
        let other = RenderEncoder(context: context)
        other.resize((width: 64, height: 64))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(owner, camera: makeCamera(), commandBuffer: commandBuffer)

        XCTAssertThrowsError(try other.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))) { error in
            XCTAssertEqual(error as? RenderSubmission.Error, .foreignEncoder)
        }
        XCTAssertFalse(submission.isConsumed, "a rejected submission stays usable")

        try owner.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)
        XCTAssertTrue(submission.isConsumed, "it draws on the encoder that made it")
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
                    guard case .destinationMismatch = error as? RenderSubmission.Error else {
                        return XCTFail("expected a destination mismatch, got \(error)")
                    }
                }
                XCTAssertTrue(renderPassDescriptor.colorAttachments[0].texture === originalTexture, "overload \(overload), \(sampleCount)x: the texture is restored")
                XCTAssertTrue(renderPassDescriptor.colorAttachments[0].resolveTexture === originalResolveTexture, "overload \(overload), \(sampleCount)x: the resolve texture is restored")
            }
        }
    }

    func testADrawnSubmissionRejectsASecondDrawAndAnotherRecord() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let submission = try makeSubmission(encoder, camera: makeCamera())
        try encoder.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))

        XCTAssertThrowsError(try encoder.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))) { error in
            XCTAssertEqual(error as? RenderSubmission.Error, .alreadyDrawn)
        }
        XCTAssertThrowsError(try submission.record(scene: makeScene().root)) { error in
            XCTAssertEqual(error as? RenderSubmission.Error, .alreadyDrawn)
        }
    }

    func testSubmissionsOnOneCommandBufferEncodeInDrawOrder() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let sink = CapturedValueSink()
        let material = CapturingMaterial(context: context)
        material.sink = sink
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        let root = Object(context: context, label: "Ordered", [mesh])
        mesh.update()

        let first = try makeSubmission(encoder, camera: makeCamera(), commandBuffer: commandBuffer)
        let second = try makeSubmission(encoder, camera: makeCamera(), commandBuffer: commandBuffer)
        material.capturedValue = 2
        try second.record(scene: root)
        material.capturedValue = 1
        try first.record(scene: root)

        try encoder.draw(submission: first, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))
        try encoder.draw(submission: second, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertNil(commandBuffer.error)
        XCTAssertEqual(sink.values, [1, 2], "each submission encodes when it is drawn, whatever order they were recorded in")
    }

    func testRetainUntilCompletedKeepsAnOwnerUntilItsCommandBufferCompletes() throws {
        final class Owner {}
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        weak var completedOwner: Owner?
        weak var abandonedOwner: Owner?

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera(), commandBuffer: commandBuffer)
        do {
            let owner = Owner()
            completedOwner = owner
            submission.retainUntilCompleted(owner)
        }
        try encoder.draw(submission: submission, renderPassDescriptor: makeRenderPassDescriptor(), scene: Object(context: context))
        XCTAssertNotNil(completedOwner, "kept alive while the command buffer is in flight")
        complete(commandBuffer)
        XCTAssertNil(completedOwner, "and released once it completes")

        try autoreleasepool {
            let abandoned = try makeSubmission(encoder, camera: makeCamera())
            let owner = Owner()
            abandonedOwner = owner
            abandoned.retainUntilCompleted(owner)
        }
        // Reclaiming happens on the arena's next allocation.
        _ = try makeSubmission(encoder, camera: makeCamera()).encodingContext.allocate(length: 16)
        XCTAssertNil(abandonedOwner, "an abandoned command buffer's owners are released when its region is reclaimed")
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
