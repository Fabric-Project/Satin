@testable import Satin
import Metal
import simd
import XCTest

/// A post processor draws its quad through its post-process encoder alone, so the load and store
/// settings it is made with, or given later, are the ones its pass uses.
final class PostProcessEncoderTests: XCTestCase {
    private var device: MTLDevice!
    private var context: Context!
    private var commandQueue: MTLCommandQueue!
    private let size = 8

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    /// A target cleared to red, readable on the CPU.
    private func makeRedTarget() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))

        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = target
        clear.colorAttachments[0].loadAction = .clear
        clear.colorAttachments[0].storeAction = .store
        clear.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: clear)).endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return target
    }

    /// Draws a fully transparent, alpha-blended quad over a red target with `processor`, and
    /// returns the centre pixel as BGRA bytes.
    private func drawTransparentQuad(with processor: PostProcessEncoder) throws -> [UInt8] {
        let target = try makeRedTarget()
        processor.resize(size: (width: Float(size), height: Float(size)), scaleFactor: 1)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        try processor.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, renderTarget: target)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixel = [UInt8](repeating: 0, count: 4)
        target.getBytes(&pixel, bytesPerRow: 4 * size, from: MTLRegionMake2D(size / 2, size / 2, 1, 1), mipmapLevel: 0)
        return pixel
    }

    private func makeProcessor(colorLoadAction: MTLLoadAction) -> PostProcessEncoder {
        PostProcessEncoder(
            context: context,
            material: BasicColorMaterial(context: context, color: .zero, blending: .alpha),
            clearColor: [0, 0, 1, 1],
            colorLoadAction: colorLoadAction
        )
    }

    func testALoadingProcessorKeepsWhatTheTargetHeld() throws {
        XCTAssertEqual(try drawTransparentQuad(with: makeProcessor(colorLoadAction: .load)), [0, 0, 255, 255], "red, as BGRA")
    }

    func testAClearingProcessorClearsToItsClearColor() throws {
        XCTAssertEqual(try drawTransparentQuad(with: makeProcessor(colorLoadAction: .clear)), [255, 0, 0, 255], "blue, as BGRA")
    }

    func testALoadActionSetLaterIsTheOneItsPassUses() throws {
        let processor = makeProcessor(colorLoadAction: .clear)
        processor.postProcessRenderer.colorLoadAction = .load
        XCTAssertEqual(try drawTransparentQuad(with: processor), [0, 0, 255, 255], "red, as BGRA")
    }
}
