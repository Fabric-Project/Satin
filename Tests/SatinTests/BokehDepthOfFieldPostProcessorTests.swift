import Metal
@testable import Satin
import XCTest

final class BokehDepthOfFieldPostProcessEncoderTests: XCTestCase {
    private func makeDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }

    private func makeContext(device: MTLDevice, colorPixelFormat: MTLPixelFormat = .rgba32Float) -> Context {
        Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: .depth32Float
        )
    }

    func testExplicitCoCBandsOverrideCompatibilityMapping() {
        guard let device = makeDevice() else { return }
        let processor = BokehDepthOfFieldPostProcessEncoder(context: makeContext(device: device))
        processor.focusDistance = 120.0
        processor.focusRange = 20.0
        processor.blend = 1.75
        processor.explicitCoCBands = .init(nearBegin: 2.0, nearEnd: 3.0, farBegin: 7.0, farEnd: 9.0)

        let settings = processor.resolvedSettings()

        XCTAssertEqual(settings.blend, 1.75, accuracy: 0.0001)
        XCTAssertEqual(settings.nearBegin, 2.0, accuracy: 0.0001)
        XCTAssertEqual(settings.nearEnd, 3.0, accuracy: 0.0001)
        XCTAssertEqual(settings.farBegin, 7.0, accuracy: 0.0001)
        XCTAssertEqual(settings.farEnd, 9.0, accuracy: 0.0001)
    }

    func testCompatibilityMappingSupportsSceneScaleBeyondLegacyCap() {
        guard let device = makeDevice() else { return }
        let processor = BokehDepthOfFieldPostProcessEncoder(context: makeContext(device: device))
        processor.focusDistance = 120.0
        processor.focusRange = 20.0

        let settings = processor.resolvedSettings()

        XCTAssertEqual(settings.nearBegin, 90.0, accuracy: 0.0001)
        XCTAssertEqual(settings.nearEnd, 110.0, accuracy: 0.0001)
        XCTAssertEqual(settings.farBegin, 130.0, accuracy: 0.0001)
        XCTAssertEqual(settings.farEnd, 150.0, accuracy: 0.0001)
    }

    func testResizeAllocatesReferenceTextureFormats() {
        guard let device = makeDevice() else { return }
        let processor = BokehDepthOfFieldPostProcessEncoder(context: makeContext(device: device))
        processor.resize(size: (64, 32), scaleFactor: 1.0)

        XCTAssertEqual(processor.fullResolutionCoCTexture?.pixelFormat, .rg16Float)
        XCTAssertEqual(processor.downsampledCoCTexture?.pixelFormat, .rg16Float)
        XCTAssertEqual(processor.nearCoCBoxIntermediateTexture?.pixelFormat, .r16Float)
        XCTAssertEqual(processor.nearCoCBoxTexture?.pixelFormat, .r16Float)
        XCTAssertEqual(processor.nearCoCMaxIntermediateTexture?.pixelFormat, .r16Float)
        XCTAssertEqual(processor.nearCoCTexture?.pixelFormat, .r16Float)
        XCTAssertEqual(processor.farWeightsTexture?.pixelFormat, .r16Float)
    }

    func testCompositePreservesSourceAlphaInSharpRegion() throws {
        guard let device = makeDevice() else { return }
        let context = makeContext(device: device)
        let processor = BokehDepthOfFieldPostProcessEncoder(context: context)
        let camera = PerspectiveCamera(context: context, position: [0.0, 0.0, 2.0], near: 0.1, far: 100.0, fov: 45.0)
        camera.aspect = 1.0

        let colorTexture = try makeColorTexture(device: device, width: 4, height: 4, rgba: [0.8, 0.4, 0.2, 0.25])
        let depthTexture = try makeDepthTexture(device: device, width: 4, height: 4, depth: 1.0)
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())

        processor.colorTexture = colorTexture
        processor.depthTexture = depthTexture
        processor.sceneCamera = camera
        processor.explicitCoCBands = .init(nearBegin: 0.01, nearEnd: 0.05, farBegin: 0.2, farEnd: 0.3)
        processor.blend = 1.0
        processor.maxBlurRadius = 4.0
        processor.resize(size: (4, 4), scaleFactor: 1.0)

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        processor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)

        let outputTexture = try XCTUnwrap(processor.outputTexture)
        let alpha = try readFirstPixelAlpha(texture: outputTexture, device: device, commandQueue: commandQueue)
        XCTAssertEqual(alpha, 0.25, accuracy: 0.02)
    }

    func testCompositeAllowsBlurCoverageOverClearedBackground() throws {
        guard let device = makeDevice() else { return }
        let context = makeContext(device: device)
        let processor = BokehDepthOfFieldPostProcessEncoder(context: context)
        let camera = PerspectiveCamera(context: context, position: [0.0, 0.0, 2.0], near: 0.1, far: 100.0, fov: 45.0)
        camera.aspect = 1.0

        let colorTexture = try makeColorTexture(device: device, width: 4, height: 4, rgba: [0.8, 0.4, 0.2, 0.0])
        let depthTexture = try makeDepthTexture(device: device, width: 4, height: 4, depth: 0.0)
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())

        processor.colorTexture = colorTexture
        processor.depthTexture = depthTexture
        processor.sceneCamera = camera
        processor.explicitCoCBands = .init(nearBegin: 0.01, nearEnd: 0.05, farBegin: 10.0, farEnd: 20.0)
        processor.blend = 1.0
        processor.maxBlurRadius = 4.0
        processor.resize(size: (4, 4), scaleFactor: 1.0)

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        processor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)

        let outputTexture = try XCTUnwrap(processor.outputTexture)
        let alpha = try readFirstPixelAlpha(texture: outputTexture, device: device, commandQueue: commandQueue)
        XCTAssertGreaterThan(alpha, 0.1)
    }

    private func makeColorTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        rgba: [Float]
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead

        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pixel = Array(rgba.prefix(4))
        var pixels = [Float](repeating: 0.0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index + 0] = pixel[0]
            pixels[index + 1] = pixel[1]
            pixels[index + 2] = pixel[2]
            pixels[index + 3] = pixel[3]
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * MemoryLayout<Float>.size * 4
        )
        return texture
    }

    private func makeDepthTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        depth: Float
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead

        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pixels = [Float](repeating: depth, count: width * height)
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * MemoryLayout<Float>.size
        )
        return texture
    }

    private func readFirstPixelAlpha(
        texture: MTLTexture,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> Float {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]

        let stagingTexture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let blitEncoder = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blitEncoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
            to: stagingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)

        var pixel = [Float](repeating: 0.0, count: 4)
        stagingTexture.getBytes(
            &pixel,
            bytesPerRow: MemoryLayout<Float>.size * 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )
        return pixel[3]
    }
}
