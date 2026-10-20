@testable import Satin
import Metal
import XCTest

/// Packets: a draw is kept only when its material set a pipeline, every packet of a recording starts
/// with the commands shared before its first material, custom commands keep their recorded order, a
/// custom draw finishes a packet without a built-in draw call, double-sided transparent renderables
/// record all front-culled draws before all back-culled ones, and storage is leased per draw.
final class PacketEncodingTests: XCTestCase {
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

    // MARK: - Custom Commands

    func testCustomCommandsKeepTheirRecordedOrder() throws {
        let storage = PacketStorage()
        beginRecording(storage)
        storage.beginMaterial()
        storage.setPipeline(try pipeline())
        storage.appendVertexBuffer(try buffer(), offset: 0, slot: .Vertices)
        storage.appendCustomCommand { _ in }
        storage.appendFragmentBuffer(try buffer(), offset: 0, slot: .MaterialUniforms)
        storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        storage.endRecording()

        let recorded = Array(commands(of: try XCTUnwrap(storage.packets.first), in: storage))
        XCTAssertEqual(recorded.count, 3)
        guard case .vertexBuffer = recorded[0], case .custom = recorded[1], case .fragmentBuffer = recorded[2] else {
            return XCTFail("a state-setting custom command sits between the bindings recorded around it")
        }
    }

    func testACustomDrawFinishesThePacketWithoutABuiltInDrawCall() throws {
        let storage = PacketStoragePool().lease()
        let commandBuffer = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        let recorder = PacketRecorder(storage: storage, arena: FrameArena(device: device), commandBuffer: commandBuffer, frame: .zero)
        let vertexUniforms = VertexUniformsBinding(buffer: try buffer(), offset: 0)
        beginRecording(storage)
        let drawContext = RenderableDrawContext(renderContext: context, pass: .color, materialPass: .all, vertexUniforms: vertexUniforms, recorder: recorder)
        _ = drawContext.materialContext(layout: nil)
        storage.setPipeline(try pipeline())
        drawContext.addCustomDraw { _ in }
        storage.endRecording()

        let packet = try XCTUnwrap(storage.packets.first)
        guard case .custom = packet.drawCall else { return XCTFail("a custom draw issues the draw call itself") }
        guard case .custom = commands(of: packet, in: storage).last else { return XCTFail("the custom draw is the packet's last command") }
    }

    // MARK: - Recording Renderables

    func testDoubleSidedTransparentRecordsFrontCulledThenBackCulled() throws {
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, arena: FrameArena(device: device), commandBuffer: commandBuffer, frame: .zero)

        let material = CustomCommandMaterial(context: context)
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
        let customCommands = storage.commands.filter { if case .custom = $0 { return true } else { return false } }.count
        XCTAssertEqual(customCommands, 2, "the material's custom command is recorded once per culled draw")
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

        first.appendCustomCommand { _ in }
        pool.returnStorage(first)
        let reused = pool.lease()
        XCTAssertTrue(reused === first)
        XCTAssertTrue(reused.commands.isEmpty)
        XCTAssertTrue(reused.customCommands.isEmpty)
    }
}
