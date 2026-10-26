@testable import Satin
import Foundation
import Metal
import XCTest

/// Real processor updates must preserve registered-buffer writes and release their command context.
final class ComputeWritableBufferTests: XCTestCase {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var directory: URL!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewCompute-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    final class WritingProcessor: TextureComputeProcessor {
        override func createShader() -> ComputeShader {
            let shader = ComputeShader(label: "Review Write", resetFunctionName: "reviewWriteReset",
                                       updateFunctionName: "reviewWriteUpdate", pipelineURL: pipelineURL)
            shader.delegate = self
            return shader
        }
    }

    private func makeProcessor() throws -> WritingProcessor {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void reviewWriteReset(uint2 gid [[thread_position_in_grid]],
                                     device uint *values [[buffer(\(ComputeBufferIndex.Custom0.rawValue))]],
                                     texture2d<float, access::write> output [[texture(\(ComputeTextureIndex.Custom0.rawValue))]]) {
            if (gid.x == 0 && gid.y == 0) { values[0] = 1234u; values[1] = 5678u; }
            output.write(float4(1), gid);
        }
        kernel void reviewWriteUpdate(uint2 gid [[thread_position_in_grid]],
                                      device uint *values [[buffer(\(ComputeBufferIndex.Custom0.rawValue))]],
                                      texture2d<float, access::write> output [[texture(\(ComputeTextureIndex.Custom0.rawValue))]]) {
            if (gid.x == 0 && gid.y == 0) { values[0] = 1234u; values[1] = 5678u; }
            output.write(float4(1), gid);
        }
        """
        let url = directory.appendingPathComponent("ReviewWrite.metal")
        try source.write(to: url, atomically: true, encoding: .utf8)
        let processor = WritingProcessor(device: device, pipelineURL: url)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        processor.set(device.makeTexture(descriptor: descriptor), index: .Custom0)
        return processor
    }

    func testKernelWritesIntoRegisteredStructBufferAreVisible() throws {
        for count in [4, 2048] { // 16 bytes (setBytes path) and 8 KB (arena copy path)
            let processor = try makeProcessor()
            let values = StructBuffer<UInt32>(device: device, count: count)
            values.update(data: [UInt32](repeating: 0, count: count))
            processor.set(values, index: .Custom0)
            let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
            try processor.update(commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            XCTAssertEqual(commandBuffer.status, .completed, String(describing: commandBuffer.error))
            XCTAssertNotNil(processor.updatePipeline, "pipeline compiled")
            let read = values.buffer.contents().advanced(by: values.offset).assumingMemoryBound(to: UInt32.self)
            XCTAssertEqual([read[0], read[1]], [1234, 5678], "\(count * 4) byte StructBuffer lost kernel writes")
        }
    }

    func testProcessorDoesNotRetainLastCommandBuffer() throws {
        let processor = try makeProcessor()
        let values = StructBuffer<UInt32>(device: device, count: 4)
        values.update(data: [0, 0, 0, 0])
        processor.set(values, index: .Custom0)
        weak var weakCommandBuffer: MTLCommandBuffer?
        try autoreleasepool {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            weakCommandBuffer = commandBuffer
            try processor.update(commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        XCTAssertNil(weakCommandBuffer, "processor keeps the committed command buffer alive")
        withExtendedLifetime(processor) {}
    }
}
