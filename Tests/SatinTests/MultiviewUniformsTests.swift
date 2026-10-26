@testable import Satin
import Metal
import simd
import XCTest

/// With vertex amplification, one render event writes every view's uniforms contiguously, as the
/// shaders index them by view, and records a single draw that amplification spreads over the views.
final class MultiviewUniformsTests: XCTestCase {
    func testOneEventWritesEveryViewContiguouslyAndRecordsOneDraw() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        guard device.supportsVertexAmplificationCount(2) else { throw XCTSkip("Vertex amplification is unavailable") }
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float, vertexAmplificationCount: 2)
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: FrameArena(device: device).lease(frame: .zero))

        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
        mesh.update()
        mesh.beginOccurrence(frame: .zero)
        let cameras = [
            PerspectiveCamera(context: context, position: [-1, 0, 5], near: 0.1, far: 100, fov: 30),
            PerspectiveCamera(context: context, position: [1, 0, 5], near: 0.1, far: 100, fov: 30),
        ]
        let viewport = simd_float4(0, 0, 64, 64)

        let packets = try recorder.record(mesh, renderContext: context, pass: .color, materialPass: .all, views: cameras.map { RenderView(camera: $0, viewport: viewport) })

        XCTAssertEqual(packets.count, 1, "one draw covers both views")
        let packet = storage.packets[packets.lowerBound]
        let commands = storage.commands[Int(packet.commandStart) ..< Int(packet.commandStart + packet.commandCount)]
        let binding = commands.compactMap { command -> (bufferIndex: Int32, offset: Int)? in
            if case let .perViewVertexBuffer(bufferIndex, offset, .VertexUniforms) = command { return (bufferIndex, offset) }
            return nil
        }.first
        let vertexUniforms = try XCTUnwrap(binding, "the mesh binds its event's vertex uniforms")
        storage.writeVertexUniforms()
        let contents = storage.buffers[Int(vertexUniforms.bufferIndex)].contents() + vertexUniforms.offset

        // viewMatrix follows modelMatrix in each view's VertexUniforms.
        let viewMatrixOffset = MemoryLayout<simd_float4x4>.stride
        for (view, camera) in cameras.enumerated() {
            let viewMatrix = (contents + view * PacketRecorder.vertexUniformsStride + viewMatrixOffset).load(as: simd_float4x4.self)
            XCTAssertEqual(viewMatrix, camera.viewMatrix, "view \(view) is written from its own camera")
        }
    }
}
