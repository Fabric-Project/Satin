@testable import Satin
import Metal
import simd
import XCTest

/// Packets: a draw is kept only when its material set a pipeline, every packet of a recording starts
/// with the commands shared before its first material, encoder state the contexts don't otherwise
/// model (object and mesh stages, tessellation factors, patch and mesh-threadgroup draws) records as
/// data, double-sided transparent renderables record all front-culled draws before all back-culled
/// ones, and storage is leased per draw.
final class PacketEncodingTests: XCTestCase {
    func testCopyOnRecordPreservesExternalBufferBytesAndOffset() throws {
        let arena = FrameArena(device: device)
        let lease = arena.lease(frame: .zero)
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: lease)
        let source = try XCTUnwrap(device.makeBuffer(length: 512, options: .storageModeShared))
        source.contents().advanced(by: 256).storeBytes(of: UInt32(42), as: UInt32.self)
        beginRecording(storage)
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        let drawContext = MaterialDrawContext(renderContext: context, pass: .color, layout: nil, recorder: recorder)
        drawContext.setVertexBuffer(source, offset: 256, index: .Vertices, copyOnRecordLength: 4)
        source.contents().advanced(by: 256).storeBytes(of: UInt32(99), as: UInt32.self)
        drawContext.setVertexBuffer(source, offset: 256, index: .VertexUniforms)
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.endRecording()
        let bindings = vertexBufferBindings(in: storage)
        XCTAssertEqual(bindings.count, 2)
        let copied = storage.buffers[Int(bindings[0].index)]
        XCTAssertFalse(copied === source)
        XCTAssertEqual((copied.contents() + bindings[0].offset).load(as: UInt32.self), 42)
        XCTAssertTrue(storage.buffers[Int(bindings[1].index)] === source)
        XCTAssertEqual(bindings[1].offset, 256)
    }

    /// The event's vertex-uniforms binding, read from the packet's commands.
    private func vertexUniformsBinding(of packets: Range<Int>, in storage: PacketStorage) -> (buffer: MTLBuffer, offset: Int)? {
        let packet = storage.packets[packets.lowerBound]
        for command in commands(of: packet, in: storage) {
            if case let .perViewVertexBuffer(bufferIndex, offset, .VertexUniforms) = command { return (storage.buffers[Int(bufferIndex)], offset) }
        }
        return nil
    }

    func testRecordingReservesVertexUniformsAndFillingWritesThem() throws {
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: FrameArena(device: device).lease(frame: .zero))
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
        mesh.position = [1, 2, 3]
        mesh.update()
        mesh.beginOccurrence(frame: .zero)
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)

        let packets = recorder.record(mesh, renderContext: context, pass: .color, materialPass: .all,
                                      views: [RenderView(camera: camera, viewport: [0, 0, 64, 64])])

        XCTAssertEqual(storage.vertexUniformsJobs.count, 1, "recording reserves the uniforms and queues their write")
        let binding = try XCTUnwrap(vertexUniformsBinding(of: packets, in: storage), "hooks still bind a real slot")
        storage.writeVertexUniforms()
        XCTAssertTrue(storage.vertexUniformsJobs.isEmpty, "a fill consumes its jobs")
        let uniforms = (binding.buffer.contents() + binding.offset).load(as: VertexUniforms.self)
        XCTAssertEqual(uniforms.modelMatrix, mesh.worldMatrix)
        XCTAssertEqual(uniforms.viewMatrix, camera.viewMatrix)
        XCTAssertEqual(uniforms.modelViewProjectionMatrix, camera.viewProjectionMatrix * mesh.worldMatrix)
    }

    func testViewsSharedByManyRecordsAreStoredOnce() throws {
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: FrameArena(device: device).lease(frame: .zero))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let views = [RenderView(camera: camera, viewport: [0, 0, 64, 64])]
        for x in 0 ..< 3 {
            let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
            mesh.position = [Float(x), 0, 0]
            mesh.update()
            mesh.beginOccurrence(frame: .zero)
            recorder.record(mesh, renderContext: context, pass: .color, materialPass: .all, views: views)
        }
        XCTAssertEqual(storage.vertexUniformsJobs.count, 3)
        XCTAssertEqual(storage.viewTable.count, 1, "three records of the same views share one table entry")
    }

    func testCopyOnRecordCopiesOnlyTheLengthAskedFor() throws {
        let lease = FrameArena(device: device).lease(frame: .zero)
        let recorder = PacketRecorder(storage: PacketStoragePool().lease(), lease: lease)
        let source = try XCTUnwrap(device.makeBuffer(length: 64 * 1024, options: .storageModeShared))
        let copied = recorder.bufferBinding(source, offset: 256, copyOnRecordLength: 4)
        let next = recorder.allocate(length: 4)
        XCTAssertTrue(next.buffer === copied.buffer)
        XCTAssertEqual(next.offset, copied.offset + 256, "4 bytes were copied, not the rest of the 64 KB buffer")
    }

    func testARingBuffersSlotIsCopiedWhenRecordedSoTheRingWrappingCantChangeIt() throws {
        let lease = FrameArena(device: device).lease(frame: .zero)
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: lease)
        let ring = StructBuffer<simd_float4>(device: device, count: 1, label: "Ring")
        let material = BasicColorMaterial(context: context)
        material.set(ring, index: FragmentBufferIndex.Custom0)
        material.update()
        ring.update(data: [simd_float4(1, 0, 0, 1)])

        beginRecording(storage)
        storage.beginMaterial()
        // A shadow pass records every slot the material set, not only those its colour shader reads.
        material.draw(in: MaterialDrawContext(renderContext: context, pass: .shadow, layout: nil, recorder: recorder))
        for _ in 0 ..< Satin.maxBuffersInFlight { ring.update(data: [simd_float4(0, 0, 1, 1)]) }
        storage.setPipeline(try pipeline())
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.endRecording()

        let binding = try XCTUnwrap(storage.commands.lazy.compactMap { command -> (index: Int32, offset: Int)? in
            if case let .fragmentBuffer(bufferIndex, offset, .Custom0) = command { return (bufferIndex, offset) }
            return nil
        }.first)
        let recorded = storage.buffers[Int(binding.index)]
        XCTAssertFalse(recorded === ring.buffer, "the recording binds its own copy, not the ring")
        XCTAssertEqual((recorded.contents() + binding.offset).load(as: simd_float4.self), simd_float4(1, 0, 0, 1),
                       "and keeps the value the ring held when it was recorded, after the ring came back to that slot")
    }

    private var context: Context!
    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func pipeline() throws -> MTLRenderPipelineState {
        let material = BasicColorMaterial(context: context)
        material.update()
        return try XCTUnwrap(material.getPipeline(renderContext: context, shadow: false))
    }

    private func buffer() throws -> MTLBuffer {
        try XCTUnwrap(device.makeBuffer(length: 256))
    }

    private func beginRecording(_ storage: PacketStorage, cullMode: MTLCullMode = .back) {
        storage.beginRecording(cullMode: cullMode, windingOrder: .counterClockwise, triangleFillMode: .fill, renderOrder: 0, debugLabel: "Test")
    }

    private func commands(of packet: DrawPacket, in storage: PacketStorage) -> ArraySlice<PacketCommand> {
        storage.commands[Int(packet.commandStart) ..< Int(packet.commandStart + packet.commandCount)]
    }

    // MARK: - Validity

    func testADrawWithoutAPipelineRecordsNoPacket() throws {
        let storage = PacketStorage()
        beginRecording(storage)
        storage.beginMaterial()
        storage.appendVertexBuffer(try buffer(), offset: 0, slot: .Vertices)
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.endRecording()

        XCTAssertTrue(storage.packets.isEmpty)
        XCTAssertTrue(storage.commands.isEmpty, "the abandoned draw's commands are rolled back")
        XCTAssertTrue(storage.buffers.isEmpty, "and so are its references")
    }

    func testAPipelineLessSecondMaterialDoesNotInheritTheFirstsPipeline() throws {
        let storage = PacketStorage()
        beginRecording(storage)
        storage.appendVertexBuffer(try buffer(), offset: 0, slot: .Vertices)

        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))

        storage.beginMaterial()
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 3, vertexCount: 3, instanceCount: 1))
        storage.endRecording()

        XCTAssertEqual(storage.packets.count, 1, "only the submesh whose material set a pipeline draws")
        XCTAssertEqual(storage.commands.count, Int(storage.packets[0].commandCount), "nothing is left after the kept packet")
    }

    func testTheSharedPrefixStartsEveryPacket() throws {
        let storage = PacketStorage()
        let pipeline = try pipeline()
        beginRecording(storage)
        storage.appendVertexBuffer(try buffer(), offset: 0, slot: .Vertices)
        for _ in 0 ..< 2 {
            storage.beginMaterial()
            storage.setPipeline(pipeline)
            storage.appendFragmentBuffer(try buffer(), offset: 0, slot: .MaterialUniforms)
            storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        }
        storage.endRecording()

        XCTAssertEqual(storage.packets.count, 2)
        for packet in storage.packets {
            guard case .vertexBuffer(_, _, .Vertices) = commands(of: packet, in: storage).first else {
                return XCTFail("each packet starts with the geometry binding recorded before its material")
            }
        }
    }

    // MARK: - Typed Commands

    func testObjectAndMeshStageBuffersAndAMeshThreadgroupDrawRecordAsData() throws {
        let storage = PacketStorage()
        let vertices = try buffer()
        let uniforms = try buffer()
        beginRecording(storage)
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.appendObjectBuffer(vertices, offset: 16, slot: .Vertices)
        storage.appendMeshBuffer(uniforms, offset: 32, slot: .MaterialUniforms)
        storage.finishPacket(drawCall: .meshThreadgroups(MTLSize(width: 4, height: 1, depth: 1),
                                                          threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                                          threadsPerMeshThreadgroup: MTLSize(width: 36, height: 1, depth: 1)))
        storage.endRecording()

        let packet = try XCTUnwrap(storage.packets.first)
        let recorded = Array(commands(of: packet, in: storage))
        guard recorded.count == 2,
              case let .objectBuffer(objectIndex, objectOffset, .Vertices) = recorded[0],
              case let .meshBuffer(meshIndex, meshOffset, .MaterialUniforms) = recorded[1]
        else { return XCTFail("object- and mesh-stage bindings record in order: \(recorded)") }
        XCTAssertTrue(storage.buffers[Int(objectIndex)] === vertices)
        XCTAssertEqual(objectOffset, 16)
        XCTAssertTrue(storage.buffers[Int(meshIndex)] === uniforms)
        XCTAssertEqual(meshOffset, 32)
        guard case let .meshThreadgroups(threadgroups, _, perMesh) = packet.drawCall else {
            return XCTFail("the packet draws mesh threadgroups")
        }
        XCTAssertEqual(threadgroups.width, 4)
        XCTAssertEqual(perMesh.width, 36)
    }

    func testTessellationFactorsAndPatchDrawsRecordAsData() throws {
        let storage = PacketStorage()
        let factors = try buffer()
        let controlPointIndices = try buffer()
        beginRecording(storage)
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.appendTessellationFactorBuffer(factors, offset: 64, instanceStride: 0)
        storage.finishPacket(drawCall: .patches(controlPointCount: 3, patchCount: 8, instanceCount: 2))
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        let indexEntry = storage.appendIndexBuffer(controlPointIndices)
        storage.finishPacket(drawCall: .indexedPatches(controlPointCount: 3, patchCount: 8, controlPointIndexBufferIndex: indexEntry, instanceCount: 1))
        storage.endRecording()

        XCTAssertEqual(storage.packets.count, 2)
        guard case let .tessellationFactorBuffer(factorIndex, factorOffset, _) = commands(of: storage.packets[0], in: storage).first else {
            return XCTFail("the factor buffer is a recorded command")
        }
        XCTAssertTrue(storage.buffers[Int(factorIndex)] === factors)
        XCTAssertEqual(factorOffset, 64)
        guard case let .patches(controlPoints, patchCount, instanceCount) = storage.packets[0].drawCall else {
            return XCTFail("the first packet draws patches")
        }
        XCTAssertEqual([controlPoints, patchCount, instanceCount], [3, 8, 2])
        guard case let .indexedPatches(_, _, recordedIndexEntry, _) = storage.packets[1].drawCall else {
            return XCTFail("the second packet draws indexed patches")
        }
        XCTAssertTrue(storage.buffers[Int(recordedIndexEntry)] === controlPointIndices)
    }

    func testMeshStageVertexUniformsFollowTheViewBeingEncoded() throws {
        let storage = PacketStorage()
        let vertexUniforms = VertexUniformsBinding(buffer: try buffer(), offset: 0)
        storage.beginRecording(cullMode: .back, windingOrder: .counterClockwise, triangleFillMode: .fill, renderOrder: 0,
                               vertexUniforms: vertexUniforms, debugLabel: "Test")
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.appendMeshBuffer(vertexUniforms.buffer, offset: vertexUniforms.offset, slot: .VertexUniforms)
        storage.appendObjectBuffer(vertexUniforms.buffer, offset: vertexUniforms.offset, slot: .VertexUniforms)
        storage.finishPacket(drawCall: .meshThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                                          threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                                          threadsPerMeshThreadgroup: MTLSize(width: 1, height: 1, depth: 1)))
        storage.endRecording()

        let recorded = Array(commands(of: try XCTUnwrap(storage.packets.first), in: storage))
        guard recorded.count == 2, case .perViewMeshBuffer = recorded[0], case .perViewObjectBuffer = recorded[1] else {
            return XCTFail("the event's own vertex uniforms follow the view in every stage: \(recorded)")
        }
    }

    // MARK: - Recording Renderables

    func testDoubleSidedTransparentRecordsFrontCulledThenBackCulled() throws {
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: FrameArena(device: device).lease(frame: .zero))

        let material = BasicColorMaterial(context: context)
        material.blending = .alpha
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        mesh.doubleSided = true
        mesh.cullMode = .none
        mesh.update()
        mesh.beginOccurrence(frame: .zero)

        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let packets = recorder.record(mesh, renderContext: context, pass: .color, materialPass: .all, views: [RenderView(camera: camera, viewport: simd_float4(0, 0, 64, 64))])

        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(storage.packets[packets.lowerBound].cullMode, .front)
        XCTAssertEqual(storage.packets[packets.lowerBound + 1].cullMode, .back)
    }

    // MARK: - Buffer Entries

    /// The buffer and offset each `vertexBuffer` command of `storage` binds, in order.
    private func vertexBufferBindings(in storage: PacketStorage) -> [(index: Int32, offset: Int)] {
        storage.commands.compactMap { command in
            if case let .vertexBuffer(bufferIndex, offset, _) = command { return (bufferIndex, offset) }
            return nil
        }
    }

    func testTheSameBufferInOneRecordingIsOneEntryWithEachCommandsOffset() throws {
        let storage = PacketStorage()
        let shared = try buffer()
        beginRecording(storage)
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.appendVertexBuffer(shared, offset: 0, slot: .Vertices)
        storage.appendVertexBuffer(shared, offset: 64, slot: .VertexUniforms)
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.endRecording()

        XCTAssertEqual(storage.buffers.count, 1, "one entry, one retain")
        let bindings = vertexBufferBindings(in: storage)
        XCTAssertEqual(bindings.map { $0.index }, [0, 0])
        XCTAssertEqual(bindings.map { $0.offset }, [0, 64], "each command keeps its own offset")
    }

    func testADifferentBufferGetsItsOwnEntry() throws {
        let storage = PacketStorage()
        beginRecording(storage)
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.appendVertexBuffer(try buffer(), offset: 0, slot: .Vertices)
        storage.appendVertexBuffer(try buffer(), offset: 0, slot: .VertexUniforms)
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.endRecording()

        XCTAssertEqual(storage.buffers.count, 2)
    }

    func testARolledBackBufferIsNotReusedByTheNextLookup() throws {
        let storage = PacketStorage()
        let rolledBack = try buffer()
        beginRecording(storage)
        storage.beginMaterial()
        storage.appendVertexBuffer(rolledBack, offset: 0, slot: .Vertices)
        // No pipeline: the packet is abandoned, and its buffer entry removed.
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.appendVertexBuffer(rolledBack, offset: 0, slot: .Vertices)
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.endRecording()

        let bindings = vertexBufferBindings(in: storage)
        XCTAssertEqual(bindings.count, 1)
        let index = Int(try XCTUnwrap(bindings.first).index)
        XCTAssertLessThan(index, storage.buffers.count, "no command references a removed entry")
        XCTAssertTrue(storage.buffers[index] === rolledBack)
    }

    func testReuseStaysWithinOneRecording() throws {
        let storage = PacketStorage()
        let shared = try buffer()
        let pipeline = try pipeline()
        for _ in 0 ..< 2 {
            beginRecording(storage)
            storage.beginMaterial()
            storage.setPipeline(pipeline)
            storage.appendVertexBuffer(shared, offset: 0, slot: .Vertices)
            storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
            storage.endRecording()
        }

        XCTAssertEqual(storage.buffers.count, 2, "each recording's packets own their entries")
    }

    // MARK: - Pool

    func testStorageIsLeasedPerDrawAndReturnedCleared() throws {
        let pool = PacketStoragePool()
        let first = pool.lease()
        let second = pool.lease()
        XCTAssertFalse(first === second, "two draws in flight never share storage")

        first.appendVertexBuffer(try buffer(), offset: 0, slot: .Vertices)
        pool.returnStorage(first)
        let reused = pool.lease()
        XCTAssertTrue(reused === first)
        XCTAssertTrue(reused.commands.isEmpty)
        XCTAssertTrue(reused.buffers.isEmpty)
    }
}
