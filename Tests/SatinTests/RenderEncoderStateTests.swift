@testable import Satin
import Metal
import simd
import XCTest

/// Custom commands: what a custom command changes holds for its own draw, and from the next packet
/// on Satin puts back what it manages (packet state, bindings, pass state) and resets what it
/// doesn't (scissor, stencil reference, blend colour, visibility) to the pass default, before its
/// own internal draws (the alpha-OIT resolve) too.
final class RenderEncoderStateTests: XCTestCase {
    private var device: MTLDevice!
    private let size = SIMD2<Int>(64, 64)

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func makeContext(alphaOit: Bool = false) throws -> Context {
        if alphaOit, !device.supportsFamily(.apple4) { throw XCTSkip("image-block OIT needs Apple4") }
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float, alphaOitEnabled: alphaOit)
    }

    /// A 1×1 texture of `color` (RGBA bytes).
    private func makeTexture(_ color: [UInt8]) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: color, bytesPerRow: 4)
        return texture
    }

    /// A quad covering the whole view of the harness camera, drawn in scene order.
    private func makeQuad(context: Context, material: Material, label: String, renderOrder: Int = 0) -> Mesh {
        let quad = Mesh(context: context, label: label, geometry: QuadGeometry(context: context, size: 10), material: material)
        quad.cullMode = .back
        quad.renderOrder = renderOrder
        return quad
    }

    /// Renders `quads` in order: by render order, unless they share one (one alpha-OIT accumulation).
    private func render(context: Context, _ quads: [Mesh], sharingRenderOrder: Bool = false) throws -> RGBAImage {
        if !sharingRenderOrder {
            for (order, quad) in quads.enumerated() { quad.renderOrder = order }
        }
        return try VisualTestHarness.render(context: context, size: size) { _, camera in
            (scene: Object(context: context, label: "Quads", quads), camera: camera)
        }
    }

    /// The RGBA bytes at the centre of `image`.
    private func centre(_ image: RGBAImage) -> [UInt8] {
        let index = ((image.height / 2) * image.width + image.width / 2) * 4
        return Array(image.pixels[index ..< index + 4])
    }

    private let red: [UInt8] = [255, 0, 0, 255]
    private let blue: [UInt8] = [0, 0, 255, 255]

    // MARK: - Packet State

    func testACustomTextureHoldsForItsOwnDraw() throws {
        let context = try makeContext()
        let material = TextureOverridingMaterial(context: context, texture: try makeTexture(red))
        material.overrideTexture = try makeTexture(blue)

        let image = try render(context: context, [makeQuad(context: context, material: material, label: "Overriding")])

        XCTAssertEqual(centre(image), blue, "the custom command's texture is what its own draw samples")
    }

    func testAPacketAfterACustomTextureBindsItsOwnAgain() throws {
        let context = try makeContext()
        let redTexture = try makeTexture(red)
        let overriding = TextureOverridingMaterial(context: context, texture: redTexture)
        overriding.overrideTexture = try makeTexture(blue)
        let plain = BasicTextureMaterial(context: context, texture: redTexture)

        let image = try render(context: context, [
            makeQuad(context: context, material: overriding, label: "Overriding"),
            makeQuad(context: context, material: plain, label: "Plain"),
        ])

        XCTAssertEqual(centre(image), red, "the second quad binds the red texture it recorded, not the cached one the command replaced")
    }

    func testAPacketAfterACustomCullModeSetsItsOwnAgain() throws {
        let context = try makeContext()
        let culling = CullOverridingMaterial(context: context, color: [0, 1, 0, 1])
        let plain = BasicColorMaterial(context: context, color: [1, 0, 0, 1])

        let image = try render(context: context, [
            makeQuad(context: context, material: culling, label: "Culling"),
            makeQuad(context: context, material: plain, label: "Plain"),
        ])

        XCTAssertEqual(centre(image), red, "the second quad culls back faces as it recorded, so it draws")
    }

    // MARK: - Unmanaged State

    func testAPacketAfterACustomScissorDrawsTheWholeTarget() throws {
        let context = try makeContext()
        let scissoring = ScissoringMaterial(context: context, color: [0, 1, 0, 1])
        let plain = BasicColorMaterial(context: context, color: [1, 0, 0, 1])

        let image = try render(context: context, [
            makeQuad(context: context, material: scissoring, label: "Scissoring"),
            makeQuad(context: context, material: plain, label: "Plain"),
        ])

        XCTAssertEqual(centre(image), red, "the scissor is reset to the whole target for the next packet")
    }

    // MARK: - Pass State

    func testAPacketAfterACustomCommandOverwritingLightingIsLitAsBefore() throws {
        let context = try makeContext()

        func renderLit(overwritingLighting: Bool) throws -> [UInt8] {
            let light = DirectionalLight(context: context, color: [1, 1, 1], intensity: 1.5)
            light.position = [0, 0, 5]
            light.lookAt(target: .zero)
            let first = LightingOverwritingMaterial(context: context, color: [0, 1, 0, 1])
            first.overwritesLighting = overwritingLighting
            let lit = BasicDiffuseMaterial(context: context, color: [1, 0, 0, 1])
            let image = try VisualTestHarness.render(context: context, size: size) { _, camera in
                (scene: Object(context: context, label: "Lit", [
                    light,
                    makeQuad(context: context, material: first, label: "First", renderOrder: 0),
                    makeQuad(context: context, material: lit, label: "Lit", renderOrder: 1),
                ]), camera: camera)
            }
            return centre(image)
        }

        XCTAssertEqual(try renderLit(overwritingLighting: true), try renderLit(overwritingLighting: false),
                       "the pass's light data is bound again before the next packet")
    }

    // MARK: - Internal Draws

    func testTheOitResolveCoversTheWholeTargetAfterACustomScissor() throws {
        let context = try makeContext(alphaOit: true)
        let covering = BasicColorMaterial(context: context, color: [1, 0, 0, 0.5], blending: .alpha)
        let scissoring = ScissoringMaterial(context: context, color: [0, 1, 0, 0.5])
        scissoring.blending = .alpha

        // Same render order: one accumulation, resolved once after the scissoring packet.
        let image = try render(context: context, [
            makeQuad(context: context, material: covering, label: "Covering"),
            makeQuad(context: context, material: scissoring, label: "Scissoring"),
        ], sharingRenderOrder: true)

        XCTAssertGreaterThan(centre(image)[0], 64, "the resolve composites the covering quad at the centre, outside the scissor")
    }

    // MARK: - Invalidation

    func testInvalidatingForgetsEveryCachedStateWithoutIssuingAny() throws {
        let context = try makeContext()
        let material = BasicColorMaterial(context: context)
        material.update()
        let pipeline = try XCTUnwrap(material.getPipeline(renderContext: context, shadow: false))
        let target = try XCTUnwrap(device.makeTexture(descriptor: {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .private
            return descriptor
        }()))
        let depthTarget = try XCTUnwrap(device.makeTexture(descriptor: {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 4, height: 4, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .private
            return descriptor
        }()))
        // Attachments matching the pipeline's: color and the context's depth format.
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = target
        renderPassDescriptor.depthAttachment.texture = depthTarget
        // Held for the test: a command buffer doesn't keep its queue alive.
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let renderEncoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor))
        defer { renderEncoder.endEncoding() }

        let state = RenderEncoderState(renderEncoder: renderEncoder, renderTargetSize: (width: 4, height: 4))
        state.pipeline = pipeline
        state.cullMode = .back
        // Nil is sent as the default state object: setDepthStencilState(nil) crashes the AGX driver.
        state.depthStencilState = nil
        state.depthBias = nil
        state.setFragmentTexture(try makeTexture(red), index: .Custom0)
        XCTAssertTrue(state.pipeline === pipeline)
        XCTAssertTrue(state.depthStencilStateIsKnown)
        XCTAssertTrue(state.depthBiasIsKnown)
        XCTAssertTrue(state.hasKnownFragmentTexture(at: FragmentTextureIndex.Custom0.rawValue))

        state.invalidate()

        XCTAssertNil(state.pipeline, "unknown: the next packet's pipeline is set again")
        XCTAssertNil(state.cullMode)
        XCTAssertFalse(state.depthStencilStateIsKnown, "a nil depth-stencil state is set again too")
        XCTAssertFalse(state.depthBiasIsKnown)
        XCTAssertFalse(state.hasKnownFragmentTexture(at: FragmentTextureIndex.Custom0.rawValue))
        XCTAssertTrue(state.passStateNeedsRestore)
        state.beginPacket()
        XCTAssertFalse(state.passStateNeedsRestore, "restored once, at the next packet")
    }
}

/// Binds `overrideTexture` at the texture slot its shader samples, after its own bindings.
private final class TextureOverridingMaterial: BasicTextureMaterial {
    override var prefix: String { "BasicTexture" }
    var overrideTexture: MTLTexture?

    override func draw(in context: MaterialDrawContext) {
        super.draw(in: context)
        guard let overrideTexture else { return }
        context.addCustomCommand { renderEncoder in
            renderEncoder.setFragmentTexture(overrideTexture, index: FragmentTextureIndex.Custom0.rawValue)
        }
    }
}

/// Culls front faces in its own draw, so it draws nothing facing the camera.
private final class CullOverridingMaterial: BasicColorMaterial {
    override var prefix: String { "BasicColor" }

    override func draw(in context: MaterialDrawContext) {
        super.draw(in: context)
        context.addCustomCommand { renderEncoder in renderEncoder.setCullMode(.front) }
    }
}

/// Scissors its own draw to the target's top-left pixel.
private final class ScissoringMaterial: BasicColorMaterial {
    override var prefix: String { "BasicColor" }

    override func draw(in context: MaterialDrawContext) {
        super.draw(in: context)
        context.addCustomCommand { renderEncoder in
            renderEncoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}

/// Overwrites the pass's light data with zeros in its own draw, when `overwritesLighting`.
private final class LightingOverwritingMaterial: BasicColorMaterial {
    override var prefix: String { "BasicColor" }
    var overwritesLighting = false

    override func draw(in context: MaterialDrawContext) {
        super.draw(in: context)
        guard overwritesLighting, let zeros = context.renderContext.device.makeBuffer(length: 4096) else { return }
        context.addCustomCommand { renderEncoder in
            renderEncoder.setFragmentBuffer(zeros, offset: 0, index: FragmentBufferIndex.Lighting.rawValue)
        }
    }
}
