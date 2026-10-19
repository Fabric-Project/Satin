@testable import Satin
import Metal
import XCTest

/// Materials, geometry and renderables record their draws through contexts: the commands match
/// what they used to bind directly, per-pass differences come from the pass, and recorded offsets
/// are captured so later changes don't alter a recorded draw.
final class DrawRecordingTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func renderableContext(pass: RenderPass, recorder: DrawRecorder) -> RenderableDrawContext {
        RenderableDrawContext(renderContext: context, pass: pass, recorder: recorder)
    }

    private func makeTexture() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        return try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
    }

    // MARK: - Geometry

    func testIndexedGeometryRecordsItsBuffersThenOneIndexedDraw() {
        let geometry = BoxGeometry(context: context)
        geometry.update()

        let unshifted = DrawRecorder()
        geometry.draw(in: renderableContext(pass: .color, recorder: unshifted).geometryContext(instanceCount: 3))
        let shifted = DrawRecorder()
        geometry.draw(in: renderableContext(pass: .color, recorder: shifted).geometryContext(instanceCount: 3, indexBufferOffset: 16))

        let vertexBufferCount = shifted.commands.filter { if case .vertexBuffer = $0 { return true } else { return false } }.count
        XCTAssertEqual(vertexBufferCount, geometry.vertexBuffers.count)

        guard case let .drawIndexedPrimitives(_, indexCount, _, _, baseOffset, _) = unshifted.commands.last,
              case let .drawIndexedPrimitives(_, _, _, _, shiftedOffset, instanceCount) = shifted.commands.last
        else {
            return XCTFail("the last command is the indexed draw")
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
        let recorder = DrawRecorder()

        material.draw(in: renderableContext(pass: .color, recorder: recorder).materialContext(layout: nil))

        XCTAssertTrue(recorder.commands.contains { if case .fragmentTexture(_, .Custom0) = $0 { return true } else { return false } })
        XCTAssertTrue(recorder.commands.contains { if case .fragmentSampler(_, .Custom0) = $0 { return true } else { return false } })
    }

    func testStandardMaterialRecordsItsMapsOnlyOutsideShadowPasses() throws {
        let material = StandardMaterial(context: context)
        material.setTexture(try makeTexture(), type: .baseColor)
        material.update()

        let color = DrawRecorder()
        material.draw(in: renderableContext(pass: .color, recorder: color).materialContext(layout: nil))
        let shadow = DrawRecorder()
        material.draw(in: renderableContext(pass: .shadow, recorder: shadow).materialContext(layout: nil))

        func recordsMaps(_ recorder: DrawRecorder) -> Bool {
            recorder.commands.contains { if case .fragmentPBRTexture = $0 { return true } else { return false } }
        }
        XCTAssertTrue(recordsMaps(color))
        XCTAssertFalse(recordsMaps(shadow))
    }

    func testOnBindIsRecordedAfterTheMaterialsOwnBindings() {
        let material = BasicColorMaterial(context: context)
        material.onBind = { _ in }
        material.update()
        let recorder = DrawRecorder()

        material.draw(in: renderableContext(pass: .color, recorder: recorder).materialContext(layout: nil))

        guard case .custom = recorder.commands.last else { return XCTFail("onBind is the last recorded command") }
    }

    func testRecordedUniformOffsetsAreCaptured() throws {
        let material = BasicColorMaterial(context: context)
        material.update()
        // Compiling the pipeline reflects which stages read the material uniforms.
        _ = material.getPipeline(renderContext: context, shadow: false)
        let recorder = DrawRecorder()
        material.draw(in: renderableContext(pass: .color, recorder: recorder).materialContext(layout: nil))

        let recordedOffsets = recorder.commands.compactMap { command -> Int? in
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

    // MARK: - Recorder

    func testResetClearsCommandsForTheNextDraw() {
        let recorder = DrawRecorder()
        recorder.record(.custom { _ in })
        recorder.reset()
        XCTAssertTrue(recorder.commands.isEmpty)
    }
}
