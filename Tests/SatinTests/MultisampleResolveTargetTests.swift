@testable import Satin
import Metal
import XCTest

/// Under MSAA, a caller's single-sample attachment is where it expects the image: the encoder renders
/// into its own multisample target and resolves into the caller's texture.
final class MultisampleResolveTargetTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func colorTarget(width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    /// Clears to red through a 4x encoder into `target` and returns the target's first pixel (BGRA).
    private func clearRed(into target: MTLTexture, encoderSize: Int) throws -> [UInt8] {
        let context = Context(device: device, sampleCount: 4, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        let encoder = RenderEncoder(context: context)
        encoder.resize((Float(encoderSize), Float(encoderSize)))
        encoder.clearColor = MTLClearColorMake(1, 0, 0, 1)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100)
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        try encoder.draw(frame: .zero, renderPassDescriptor: descriptor, commandBuffer: commandBuffer,
                         scene: Object(context: context), camera: camera)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        var pixel = [UInt8](repeating: 0, count: 4)
        target.getBytes(&pixel, bytesPerRow: target.width * 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        return pixel
    }

    func testASingleSampleColorTargetReceivesTheResolvedImage() throws {
        let target = try colorTarget(width: 32, height: 32)
        XCTAssertEqual(try clearRed(into: target, encoderSize: 32), [0, 0, 255, 255])
    }

    func testAMismatchedSingleSampleTargetFallsBackWithoutFailing() throws {
        // Not the encoder's size, so it cannot be a resolve target; the encoder resolves into its own.
        let target = try colorTarget(width: 16, height: 16)
        XCTAssertEqual(try clearRed(into: target, encoderSize: 32), [0, 0, 0, 0])
    }
}
