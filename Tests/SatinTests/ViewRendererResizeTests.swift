import Metal
@testable import Satin
import XCTest

/// View resizing reaches the renderer directly on the display owner.
final class ViewRendererResizeTests: XCTestCase {
    private final class ResizeRecordingRenderer: ViewRenderer {
        var resizes: [(width: Float, height: Float, scaleFactor: Float)] = []
        override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
            resizes.append((size.width, size.height, scaleFactor))
        }
    }

    func testTheViewsResizeAppliesAtOnce() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = ResizeRecordingRenderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
        renderer.drawableResized(size: CGSize(width: 100, height: 50), scaleFactor: 2)
        XCTAssertEqual(renderer.resizes.count, 1)
        XCTAssertEqual(renderer.resizes.first?.width, 100)
        XCTAssertEqual(renderer.resizes.first?.height, 50)
        XCTAssertEqual(renderer.resizes.first?.scaleFactor, 2)
    }
}
