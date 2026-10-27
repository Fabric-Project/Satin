@testable import Satin
import Metal
import simd
import XCTest

/// The encoder state: one per owner, reused pass to pass. Each pass starts knowing nothing, repeated
/// bindings are skipped, a nil depth-stencil state is sent as the default state object, and ending
/// a pass lets go of everything it bound.
final class RenderEncoderStateTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    /// A 1×1 texture of `color` (RGBA bytes).
    private func makeTexture(_ color: [UInt8]) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: color, bytesPerRow: 4)
        return texture
    }

    private let red: [UInt8] = [255, 0, 0, 255]

    /// A render target and encoder for one pass: returned so the caller decides when they go.
    private func makePass(_ commandBuffer: MTLCommandBuffer) throws -> MTLRenderCommandEncoder {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        return try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor))
    }

    func testANilDepthStencilStateIsSentAsTheDefaultObject() throws {
        let commandBuffer = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        let encoder = try makePass(commandBuffer)
        defer { encoder.endEncoding() }
        let state = RenderEncoderState()
        state.begin(renderEncoder: encoder)

        // setDepthStencilState(nil) crashes the AGX driver: nil is known, and sent as an object.
        state.depthStencilState = nil
        state.depthBias = nil

        XCTAssertTrue(state.depthStencilStateIsKnown)
        XCTAssertTrue(state.depthBiasIsKnown)
        state.end()
    }

    func testAReusedStateStartsEachPassClean() throws {
        let commandBuffer = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        let state = RenderEncoderState()
        let texture = try makeTexture(red)

        let first = try makePass(commandBuffer)
        state.begin(renderEncoder: first)
        state.setFragmentTexture(texture, index: .Custom0)
        XCTAssertTrue(state.hasKnownFragmentTexture(at: FragmentTextureIndex.Custom0.rawValue))
        first.endEncoding()
        state.end()

        let second = try makePass(commandBuffer)
        state.begin(renderEncoder: second)
        XCTAssertFalse(state.hasKnownFragmentTexture(at: FragmentTextureIndex.Custom0.rawValue),
                       "the second pass binds its first texture even when it equals the first pass's last")
        second.endEncoding()
        state.end()
    }

    func testBeginningAnotherPassClearsStateEvenWithoutAnExplicitStateEnd() throws {
        let commandBuffer = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        let state = RenderEncoderState()
        let first = try makePass(commandBuffer)
        state.begin(renderEncoder: first)
        state.setFragmentTexture(try makeTexture(red), index: .Custom0)
        first.endEncoding()

        let second = try makePass(commandBuffer)
        state.begin(renderEncoder: second)

        XCTAssertFalse(state.hasKnownFragmentTexture(at: FragmentTextureIndex.Custom0.rawValue))
        second.endEncoding()
        state.end()
    }

    func testEndingAPassReleasesItsReferences() throws {
        let state = RenderEncoderState()
        weak var releasedEncoder: MTLRenderCommandEncoder?
        weak var releasedBuffer: MTLBuffer?

        try autoreleasepool {
            let commandBuffer = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
            let encoder = try makePass(commandBuffer)
            let buffer = try XCTUnwrap(device.makeBuffer(length: 256))
            releasedEncoder = encoder
            releasedBuffer = buffer
            state.begin(renderEncoder: encoder)
            state.setVertexBuffer(buffer, offset: 0, index: .Vertices)
            state.setPassFragmentBuffer(buffer, offset: 0, index: .Lighting)
            encoder.endEncoding()
            state.end()
        }

        XCTAssertFalse(state.holdsPass, "the state keeps no encoder or binding after its pass")
        XCTAssertNil(releasedEncoder, "nothing in the state keeps the finished encoder")
        XCTAssertNil(releasedBuffer, "or the pass's buffers")
    }
}
