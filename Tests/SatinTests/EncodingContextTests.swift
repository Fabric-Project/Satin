@testable import Satin
import Metal
import simd
import XCTest

/// Encoding contexts: encoding and drawing see the submission's one view snapshot, every encoding
/// writes its own arena slice (tessellation factors included), and each record binds the values it
/// was recorded with.
final class EncodingContextTests: XCTestCase {
    private var device: MTLDevice!
    private var context: Context!
    private var commandQueue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func makeCamera(x: Float = 0) -> PerspectiveCamera {
        let camera = PerspectiveCamera(context: context, position: [x, 0, 5], near: 0.1, far: 100, fov: 30)
        camera.aspect = 1
        return camera
    }

    private func makeSubmission(_ encoder: RenderEncoder, camera: Camera) throws -> SubmissionBuilder {
        encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [MTLViewport(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
    }

    private func recordedPackets(_ submission: SubmissionBuilder) -> [DrawPacket] {
        let storage = submission.recorder.storage
        return storage.runs.filter(\.isRecorded).flatMap { storage.packets[$0.packets] }
    }

    private func viewMatrix(of packet: DrawPacket, in storage: PacketStorage) -> simd_float4x4? {
        storage.writeVertexUniforms()
        for command in storage.commands[Int(packet.commandStart) ..< Int(packet.commandStart + packet.commandCount)] {
            if case let .perViewVertexBuffer(bufferIndex, offset, .VertexUniforms) = command {
                // viewMatrix follows modelMatrix in VertexUniforms.
                return (storage.buffers[Int(bufferIndex)].contents() + offset + MemoryLayout<simd_float4x4>.stride).load(as: simd_float4x4.self)
            }
        }
        return nil
    }

    // MARK: - One View Snapshot

    func testEncodingAndDrawingSeeTheSubmissionsViewSnapshot() throws {
        let encoder = RenderEncoder(context: context)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let camera = makeCamera(x: 0)
        let submission = try makeSubmission(encoder, camera: camera)
        let viewAtCreation = camera.viewMatrix

        camera.position = [3, 0, 5]
        camera.update()

        let mesh = ViewRecordingMesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
        let root = Object(context: context, label: "Encoded", [mesh])
        mesh.update()
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))
        try submission.record(scene: root)

        XCTAssertEqual(mesh.encodedViewMatrix, viewAtCreation, "encoding sees the view as it was when the submission was made")
        let packet = try XCTUnwrap(recordedPackets(submission).first)
        XCTAssertEqual(viewMatrix(of: packet, in: submission.recorder.storage), mesh.encodedViewMatrix, "and so does its draw")
    }

    // MARK: - Slices

    func testTwoEncodingsBeforeEitherDrawWriteDistinctSlices() throws {
        let encoder = RenderEncoder(context: context)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        let encodingContext = submission.encodingContext(commandBuffer: commandBuffer)

        let first = encodingContext.allocate(length: 64)
        let second = encodingContext.allocate(length: 64)

        let overlaps = first.buffer === second.buffer && abs(first.offset - second.offset) < 64
        XCTAssertFalse(overlaps, "the second encoding never overwrites the first's slice")
    }

    // MARK: - Tessellation Factors

    private func makeTessellatedMesh(tessellate: Bool) -> (mesh: TessellationMesh, tessellator: RecordingTessellator) {
        let geometry = TessellationGeometry(baseGeometry: QuadGeometry(context: context, size: 1.0))
        // No shader: the recording tessellator fills each destination itself.
        let tessellator = RecordingTessellator(
            device: device,
            pipelineURL: FileManager.default.temporaryDirectory.appending(path: "MissingTessellator.metal"),
            live: false,
            geometry: geometry
        )
        let mesh = TessellationMesh(context: context, label: "Tessellated", geometry: geometry, material: nil, tessellator: tessellator, tessellate: tessellate)
        return (mesh, tessellator)
    }

    func testTessellatingWritesEachEncodingsFactorsToItsOwnSlice() throws {
        let encoder = RenderEncoder(context: context)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        let (mesh, tessellator) = makeTessellatedMesh(tessellate: true)

        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))

        XCTAssertEqual(tessellator.destinations.count, 2)
        let first = try XCTUnwrap(tessellator.destinations.first)
        let second = try XCTUnwrap(tessellator.destinations.last)
        let overlaps = first.buffer === second.buffer && abs(first.offset - second.offset) < tessellator.factorsLength
        XCTAssertFalse(overlaps, "each encoding writes its factors to its own slice")
        XCTAssertTrue(mesh.encodedFactors?.buffer === second.buffer && mesh.encodedFactors?.offset == second.offset, "and the draw binds the last")
    }

    func testTurningTessellationOffFreezesTheFactorsOnce() throws {
        let encoder = RenderEncoder(context: context)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        let (mesh, tessellator) = makeTessellatedMesh(tessellate: true)
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))

        mesh.tessellate = false
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))

        XCTAssertEqual(tessellator.destinations.count, 2, "one dispatch to freeze, then none")
        let frozen = try XCTUnwrap(tessellator.destinations.last)
        XCTAssertEqual(frozen.offset, 0)
        XCTAssertTrue(mesh.encodedFactors?.buffer === frozen.buffer, "the draw binds the frozen factors")
    }

    func testAMeshStartingUntessellatedFreezesOnItsFirstEncoding() throws {
        let encoder = RenderEncoder(context: context)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        let (mesh, tessellator) = makeTessellatedMesh(tessellate: false)

        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))

        XCTAssertEqual(tessellator.destinations.count, 1)
        XCTAssertNotNil(mesh.encodedFactors)
    }

    func testALaterFreezeNeverOverwritesAnEarlierOnesFactors() throws {
        let encoder = RenderEncoder(context: context)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())
        let (mesh, tessellator) = makeTessellatedMesh(tessellate: false)

        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))
        let firstFrozen = try XCTUnwrap(mesh.encodedFactors?.buffer)
        mesh.tessellate = true
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))
        mesh.tessellate = false
        mesh.encode(in: submission.encodingContext(commandBuffer: commandBuffer))
        let secondFrozen = try XCTUnwrap(mesh.encodedFactors?.buffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertFalse(firstFrozen === secondFrozen, "each freeze writes a new buffer")
        XCTAssertEqual(tessellator.fillValues, [1, 2, 3])
        XCTAssertEqual(try contents(of: firstFrozen, length: tessellator.factorsLength), [UInt8](repeating: 1, count: tessellator.factorsLength), "the first freeze's factors survive the second")
        XCTAssertEqual(try contents(of: secondFrozen, length: tessellator.factorsLength), [UInt8](repeating: 3, count: tessellator.factorsLength))
    }

    /// The first `length` bytes of a private `buffer`, copied back through a shared one.
    private func contents(of buffer: MTLBuffer, length: Int) throws -> [UInt8] {
        let readback = try XCTUnwrap(device.makeBuffer(length: length, options: .storageModeShared))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let blitEncoder = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blitEncoder.copy(from: buffer, sourceOffset: 0, to: readback, destinationOffset: 0, size: length)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return Array(UnsafeRawBufferPointer(start: readback.contents(), count: length))
    }

    // MARK: - Captured Values

    func testEachRecordBindsTheValuesItWasRecordedWith() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 64, height: 64))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = try makeSubmission(encoder, camera: makeCamera())

        let material = BasicColorMaterial(context: context)
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        let root = Object(context: context, label: "Captured", [mesh])
        mesh.update()

        material.color = [1, 0, 0, 1]
        try submission.record(scene: root)
        material.color = [2, 0, 0, 1]
        try submission.record(scene: root)
        material.color = [3, 0, 0, 1]

        try submission.record(scene: Object(context: context), renderPassDescriptor: makeRenderPassDescriptor(), preparationCommandBuffer: commandBuffer)
        try submission.seal().encode(into: commandBuffer)
        // Read before completion returns the storage.
        let recorded = recordedColorRed(in: submission.recorder.storage)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertEqual(recorded, [1, 2], "each record binds the value it captured, not the material's value when it encodes")
    }

    private func makeRenderPassDescriptor() throws -> MTLRenderPassDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        return renderPassDescriptor
    }
}

/// Keeps the first view matrix it was encoded with.
private final class ViewRecordingMesh: Mesh {
    private(set) var encodedViewMatrix: simd_float4x4?

    override func encode(in context: EncodingContext) {
        if encodedViewMatrix == nil { encodedViewMatrix = context.views.first?.viewMatrix }
        super.encode(in: context)
    }
}

/// Where captured values land when their commands run.
/// The red channel of the colour each packet of `storage` binds in its material uniforms, in
/// recorded order: what each record snapshotted.
func recordedColorRed(in storage: PacketStorage) -> [Float] {
    storage.packets.compactMap { packet in
        for command in storage.commands[Int(packet.commandStart) ..< Int(packet.commandStart + packet.commandCount)] {
            if case let .fragmentBuffer(bufferIndex, offset, .MaterialUniforms) = command {
                return (storage.buffers[Int(bufferIndex)].contents() + offset).load(as: Float.self)
            }
        }
        return nil
    }
}

/// Fills each dispatch's factors destination with its own byte (1, 2, 3, …) instead of running a
/// shader, and keeps where each went.
final class RecordingTessellator: TessellationProcessor<MTLTriangleTessellationFactorsHalf> {
    private(set) var destinations: [(buffer: MTLBuffer, offset: Int)] = []
    private(set) var fillValues: [UInt8] = []

    override func update(_ commandBuffer: MTLCommandBuffer, iterations: Int = 1) {
        guard let destination = factorsDestination, let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
        let value = UInt8(fillValues.count + 1)
        blitEncoder.fill(buffer: destination.buffer, range: destination.offset ..< destination.offset + factorsLength, value: value)
        blitEncoder.endEncoding()
        destinations.append(destination)
        fillValues.append(value)
    }
}
