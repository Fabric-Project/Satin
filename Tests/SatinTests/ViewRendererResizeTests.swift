import Metal
@testable import Satin
import XCTest

/// With a render queue, the view's resize can't race the frame: each frame resizes from its own
/// drawable's size, with the latest scale factor the view reported, before it updates.
final class ViewRendererResizeTests: XCTestCase {
    private final class ResizeRecordingRenderer: ViewRenderer {
        var resizes: [(width: Float, height: Float, scaleFactor: Float)] = []
        override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
            resizes.append((size.width, size.height, scaleFactor))
        }
    }

    private func makeTexture(_ device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    func testEachNewDrawableSizeResizesOnceWithTheLatestScaleFactor() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = ResizeRecordingRenderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm),
                                               renderQueue: DispatchQueue(label: "Owner"))
        renderer.drawableResized(size: CGSize(width: 100, height: 50), scaleFactor: 2)
        XCTAssertTrue(renderer.resizes.isEmpty, "the size comes with the next frame's drawable")

        let small = try makeTexture(device, width: 100, height: 50)
        let large = try makeTexture(device, width: 300, height: 200)
        renderer.resizeIfNeeded(for: small)
        renderer.resizeIfNeeded(for: small)
        renderer.resizeIfNeeded(for: large)

        XCTAssertEqual(renderer.resizes.map(\.width), [100, 300])
        XCTAssertEqual(renderer.resizes.map(\.height), [50, 200])
        XCTAssertEqual(renderer.resizes.map(\.scaleFactor), [2, 2])
    }

    func testWithoutAQueueTheViewsResizeAppliesAtOnce() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = ResizeRecordingRenderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
        renderer.drawableResized(size: CGSize(width: 100, height: 50), scaleFactor: 2)
        XCTAssertEqual(renderer.resizes.count, 1)
        XCTAssertEqual(renderer.resizes.first?.width, 100)
    }
}
