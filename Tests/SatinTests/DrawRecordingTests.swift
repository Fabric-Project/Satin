@testable import Satin
import Metal
import simd
import XCTest

/// Materials, geometry and renderables record their draws through contexts into packet storage: the
/// commands match what they used to bind directly, per-pass differences come from the pass, and
/// recorded offsets are captured so later changes don't alter a recorded draw.
final class DrawRecordingTests: XCTestCase {
    private var context: Context!
    private var commandQueue: MTLCommandQueue!
    private var arena: FrameArena!
    private let pool = PacketStoragePool()

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
        arena = FrameArena(device: device)
    }

    /// A context recording into a freshly leased storage, as one renderable's recording in `pass`.
    private func makeRecording(pass: RenderPass) throws -> (context: RenderableDrawContext, storage: PacketStorage) {
        let storage = pool.lease()
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let recorder = PacketRecorder(storage: storage, arena: arena, commandBuffer: commandBuffer, frame: .zero)
        storage.beginRecording(cullMode: .back, windingOrder: .counterClockwise, triangleFillMode: .fill, renderOrder: 0, debugLabel: "Test")
        let vertexUniformsBuffer = try XCTUnwrap(context.device.makeBuffer(length: 4096))
        let drawContext = RenderableDrawContext(
            renderContext: context,
            pass: pass,
            materialPass: .all,
            vertexUniforms: VertexUniformsBinding(buffer: vertexUniformsBuffer, offset: 0),
            recorder: recorder
        )
        return (drawContext, storage)
    }

    /// The material-uniforms bindings `storage` recorded, as (buffer, offset), in order.
    private func materialUniformBindings(in storage: PacketStorage) -> [(buffer: MTLBuffer, offset: Int)] {
        storage.commands.compactMap { command -> (buffer: MTLBuffer, offset: Int)? in
            if case let .fragmentBuffer(bufferIndex, offset, .MaterialUniforms) = command { return (storage.buffers[Int(bufferIndex)], offset) }
            if case let .vertexBuffer(bufferIndex, offset, .MaterialUniforms) = command { return (storage.buffers[Int(bufferIndex)], offset) }
            return nil
        }
    }

    private func makeTexture() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        return try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
    }

    private func pipeline() throws -> MTLRenderPipelineState {
        let material = BasicColorMaterial(context: context)
        material.update()
        return try XCTUnwrap(material.getPipeline(renderContext: context, shadow: false))
    }

    // MARK: - Geometry

    func testIndexedGeometryRecordsItsBuffersThenOneIndexedDraw() throws {
        let geometry = BoxGeometry(context: context)
        geometry.update()
        let pipeline = try pipeline()

        func recordDraw(indexBufferOffset: Int) throws -> (packet: DrawPacket, storage: PacketStorage) {
            let (drawContext, storage) = try makeRecording(pass: .color)
            _ = drawContext.materialContext(layout: nil)
            storage.setPipeline(pipeline)
            geometry.draw(in: drawContext.geometryContext(instanceCount: 3, indexBufferOffset: indexBufferOffset))
            storage.endRecording()
            XCTAssertEqual(storage.packets.count, 1)
            return (try XCTUnwrap(storage.packets.first), storage)
        }

        let unshifted = try recordDraw(indexBufferOffset: 0)
        let shifted = try recordDraw(indexBufferOffset: 16)

        let range = Int(shifted.packet.commandStart) ..< Int(shifted.packet.commandStart + shifted.packet.commandCount)
        let vertexBufferCount = shifted.storage.commands[range].filter { if case .vertexBuffer = $0 { return true } else { return false } }.count
        XCTAssertEqual(vertexBufferCount, geometry.vertexBuffers.count)

        guard case let .indexedPrimitives(_, indexCount, _, _, baseOffset, _) = unshifted.packet.drawCall,
              case let .indexedPrimitives(_, _, _, _, shiftedOffset, instanceCount) = shifted.packet.drawCall
        else {
            return XCTFail("the draw call is indexed")
        }
        XCTAssertEqual(indexCount, geometry.indexCount)
        XCTAssertEqual(shiftedOffset - baseOffset, 16, "the context's offset is added to the geometry's own")
        XCTAssertEqual(instanceCount, 3)
    }

    // MARK: - Materials

    func testBasicTextureMaterialRecordsItsTextureAndSampler() throws {
        let material = BasicTextureMaterial(context: context, texture: try makeTexture())
        // A mesh sets its material up, which creates the default sampler.
        material.setup()
        material.update()
        let (drawContext, storage) = try makeRecording(pass: .color)

        material.draw(in: drawContext.materialContext(layout: nil))

        XCTAssertTrue(storage.commands.contains { if case .fragmentTexture(_, .Custom0) = $0 { return true } else { return false } })
        XCTAssertTrue(storage.commands.contains { if case .fragmentSampler(_, .Custom0) = $0 { return true } else { return false } })
    }

    func testStandardMaterialPrunesMapsFromItsDepthOnlyShadowPipeline() throws {
        let material = StandardMaterial(context: context)
        material.castShadow = true
        material.setTexture(try makeTexture(), type: .baseColor)
        material.update()

        func recordsMaps(_ pass: RenderPass) throws -> Bool {
            let (drawContext, storage) = try makeRecording(pass: pass)
            material.draw(in: drawContext.materialContext(layout: nil))
            // Materials gather resources first; the selected pipeline prunes the finished packet.
            storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
            storage.endRecording()
            return storage.commands.contains { if case .fragmentPBRTexture = $0 { return true } else { return false } }
        }

        XCTAssertTrue(try recordsMaps(.color))
        XCTAssertFalse(try recordsMaps(.shadow))
    }

    func testASubclassCustomCommandIsRecordedAfterSupersBindings() throws {
        let material = CustomCommandMaterial(context: context)
        material.update()
        let (drawContext, storage) = try makeRecording(pass: .color)

        material.draw(in: drawContext.materialContext(layout: nil))

        XCTAssertTrue(storage.commands.dropLast().contains { if case .fragmentBuffer = $0 { return true } else { return false } }, "super's bindings come first")
        guard case .custom = storage.commands.last else { return XCTFail("the subclass's custom command is the last recorded command") }
    }

    func testRecordedUniformsAreASnapshotAndAChangeTakesANewOne() throws {
        let material = BasicColorMaterial(context: context)
        material.update()
        // Compiling the pipeline reflects which stages read the material uniforms.
        _ = material.getPipeline(renderContext: context, shadow: false)
        let size = material.parameters.size
        let (drawContext, storage) = try makeRecording(pass: .color)

        material.draw(in: drawContext.materialContext(layout: nil))
        material.draw(in: drawContext.materialContext(layout: nil))
        let unchanged = materialUniformBindings(in: storage)
        XCTAssertFalse(unchanged.isEmpty, "the material records its uniforms")
        XCTAssertTrue(unchanged.allSatisfy { $0.buffer === unchanged[0].buffer && $0.offset == unchanged[0].offset }, "an unchanged material snapshots once per lease")
        let firstBytes = Array(UnsafeRawBufferPointer(start: unchanged[0].buffer.contents() + unchanged[0].offset, count: size))

        // Changed, and drawn again with no read of `parameters.data` in between.
        material.color = [1, 0, 0, 1]
        material.draw(in: drawContext.materialContext(layout: nil))
        let changed = try XCTUnwrap(materialUniformBindings(in: storage).last)
        XCTAssertFalse(changed.buffer === unchanged[0].buffer && changed.offset == unchanged[0].offset, "a change takes a new snapshot")
        let changedBytes = Array(UnsafeRawBufferPointer(start: changed.buffer.contents() + changed.offset, count: size))
        XCTAssertNotEqual(changedBytes, firstBytes, "with the new values")
        let firstAfterChange = Array(UnsafeRawBufferPointer(start: unchanged[0].buffer.contents() + unchanged[0].offset, count: size))
        XCTAssertEqual(firstAfterChange, firstBytes, "and the first draw keeps the values it was recorded with")
    }

    // MARK: - Storage

    func testResetClearsPacketsAndCommands() throws {
        let (drawContext, storage) = try makeRecording(pass: .color)
        drawContext.addCustomCommand { _ in }
        storage.reset()
        XCTAssertTrue(storage.commands.isEmpty)
        XCTAssertTrue(storage.packets.isEmpty)
        XCTAssertTrue(storage.customCommands.isEmpty)
    }

    // MARK: - Geometry Customization

    /// Records `mesh` once in the colour pass, as an encoder does.
    private func record(_ mesh: Mesh) throws -> PacketStorage {
        let storage = pool.lease()
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let recorder = PacketRecorder(storage: storage, arena: arena, commandBuffer: commandBuffer, frame: .zero)
        mesh.update()
        mesh.beginOccurrence(frame: .zero)
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        _ = recorder.record(mesh, renderContext: context, pass: .color, materialPass: .all, views: [RenderView(camera: camera, viewport: simd_float4(0, 0, 64, 64))])
        return storage
    }

    private func indexCounts(in storage: PacketStorage) -> [Int] {
        storage.packets.compactMap { packet in
            if case let .indexedPrimitives(_, indexCount, _, _, _, _) = packet.drawCall { return indexCount }
            return nil
        }
    }

    func testAMeshDrawsItsGeometryThroughDraw() throws {
        let geometry = CountingGeometry(context: context)
        let mesh = Mesh(context: context, geometry: geometry, material: BasicColorMaterial(context: context))

        let storage = try record(mesh)

        XCTAssertEqual(geometry.drawCount, 1)
        XCTAssertEqual(storage.packets.count, 1)
    }

    func testEachSubmeshDrawsItsIndicesThroughTheMeshGeometrysDraw() throws {
        let geometry = CountingGeometry(context: context)
        geometry.update()
        let elements = try XCTUnwrap(geometry.elementBuffer)
        let mesh = Mesh(context: context, geometry: geometry, material: nil)
        for count in [elements.count, 3] {
            let submeshElements = ElementBuffer(type: elements.type, data: elements.data, count: count, source: geometry)
            mesh.addSubmesh(Submesh(context: context, elementBuffer: submeshElements, material: BasicColorMaterial(context: context)))
        }

        let storage = try record(mesh)

        XCTAssertEqual(geometry.drawCount, 2, "one draw per submesh, through the geometry's own draw")
        XCTAssertEqual(indexCounts(in: storage), [elements.count, 3], "each over its submesh's indices")
    }

    func testAPosedViewDrawsThroughItsSourcesDraw() throws {
        let source = CountingGeometry(context: context)
        let mesh = Mesh(context: context, geometry: PosedGeometry(source: source), material: BasicColorMaterial(context: context))

        let storage = try record(mesh)

        XCTAssertEqual(source.drawCount, 1, "a custom source's draw is honoured when posed")
        XCTAssertEqual(storage.packets.count, 1)
    }

    func testADoubleSidedTransparentMeshDrawsItsGeometryPerCulledDraw() throws {
        let geometry = CountingGeometry(context: context)
        let material = BasicColorMaterial(context: context)
        material.blending = .alpha
        let mesh = Mesh(context: context, geometry: geometry, material: material)
        mesh.doubleSided = true
        mesh.cullMode = .none

        let storage = try record(mesh)

        XCTAssertEqual(geometry.drawCount, 2)
        XCTAssertEqual(storage.packets.count, 2)
    }
}

/// Records one custom command after the material's own bindings, as a subclass customising its
/// encoding does.
final class CustomCommandMaterial: BasicColorMaterial {
    // The shader is found by class name: draw with BasicColor's.
    override var prefix: String { "BasicColor" }

    override func draw(in context: MaterialDrawContext) {
        super.draw(in: context)
        context.addCustomCommand { _ in }
    }
}

/// Counts its draws and draws a quad, as a geometry customising its draw from outside Satin would:
/// it overrides only `draw(in:)`.
final class CountingGeometry: SatinGeometry {
    private(set) var drawCount = 0

    override func generateGeometryData() -> GeometryData {
        generateQuadGeometryData(1)
    }

    override func draw(in context: GeometryDrawContext) {
        drawCount += 1
        super.draw(in: context)
    }
}
