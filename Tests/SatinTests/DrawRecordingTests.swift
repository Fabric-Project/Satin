@testable import Satin
import Metal
import XCTest

/// Materials, geometry and renderables record their draws through contexts into packet storage: the
/// commands match what they used to bind directly, per-pass differences come from the pass, and
/// recorded offsets are captured so later changes don't alter a recorded draw.
final class DrawRecordingTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    /// A context recording into a fresh storage, as one renderable's recording in `pass`.
    private func makeRecording(pass: RenderPass) throws -> (context: RenderableDrawContext, storage: PacketStorage) {
        let storage = PacketStorage()
        storage.beginRecording(cullMode: .back, windingOrder: .counterClockwise, triangleFillMode: .fill, renderOrder: 0, debugLabel: "Test")
        let vertexUniformsBuffer = try XCTUnwrap(context.device.makeBuffer(length: 4096))
        let drawContext = RenderableDrawContext(
            renderContext: context,
            pass: pass,
            materialPass: .all,
            vertexUniforms: VertexUniformsBinding(buffer: vertexUniformsBuffer, offset: 0),
            storage: storage
        )
        return (drawContext, storage)
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

    func testStandardMaterialRecordsItsMapsOnlyOutsideShadowPasses() throws {
        let material = StandardMaterial(context: context)
        material.setTexture(try makeTexture(), type: .baseColor)
        material.update()

        func recordsMaps(_ pass: RenderPass) throws -> Bool {
            let (drawContext, storage) = try makeRecording(pass: pass)
            material.draw(in: drawContext.materialContext(layout: nil))
            return storage.commands.contains { if case .fragmentPBRTexture = $0 { return true } else { return false } }
        }

        XCTAssertTrue(try recordsMaps(.color))
        XCTAssertFalse(try recordsMaps(.shadow))
    }

    func testOnBindIsRecordedAfterTheMaterialsOwnBindings() throws {
        let material = BasicColorMaterial(context: context)
        material.onBind = { _ in }
        material.update()
        let (drawContext, storage) = try makeRecording(pass: .color)

        material.draw(in: drawContext.materialContext(layout: nil))

        guard case .custom = storage.commands.last else { return XCTFail("onBind is the last recorded command") }
    }

    func testRecordedUniformOffsetsAreCaptured() throws {
        let material = BasicColorMaterial(context: context)
        material.update()
        // Compiling the pipeline reflects which stages read the material uniforms.
        _ = material.getPipeline(renderContext: context, shadow: false)
        let (drawContext, storage) = try makeRecording(pass: .color)
        material.draw(in: drawContext.materialContext(layout: nil))

        let recordedOffsets = storage.commands.compactMap { command -> Int? in
            if case let .fragmentBuffer(_, offset, .MaterialUniforms) = command { return offset }
            if case let .vertexBuffer(_, offset, .MaterialUniforms) = command { return offset }
            return nil
        }
        let uniforms = try XCTUnwrap(material.uniforms)
        let offsetWhenRecorded = uniforms.offset

        material.color = [1, 0, 0, 1]
        material.update()

        XCTAssertFalse(recordedOffsets.isEmpty, "the material records its uniforms")
        XCTAssertTrue(recordedOffsets.allSatisfy { $0 == offsetWhenRecorded }, "a later update doesn't move a recorded binding")
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
}
