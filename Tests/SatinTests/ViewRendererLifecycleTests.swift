#if os(macOS)
import AppKit
import Metal
@testable import Satin
import XCTest

final class ViewRendererLifecycleTests: XCTestCase {
    private final class LifecycleRenderer: ViewRenderer {
        var setups = 0
        var cleanups = 0
        var lifecycleStayedOnMain = true

        override func setup() throws {
            setups += 1
            lifecycleStayedOnMain = lifecycleStayedOnMain && Thread.isMainThread
        }

        override func cleanup() throws {
            cleanups += 1
            lifecycleStayedOnMain = lifecycleStayedOnMain && Thread.isMainThread
        }
    }

    @MainActor
    func testCleanupFinishesBeforeRendererIsReattached() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = LifecycleRenderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))

        autoreleasepool {
            let first = MetalViewController(renderer: renderer)
            _ = first.view
            XCTAssertTrue(renderer.isSetup)
            XCTAssertTrue(first.metalView.delegate === renderer)

            first.cleanup()
            XCTAssertFalse(renderer.isSetup)
            XCTAssertNil(first.metalView.delegate)
            XCTAssertEqual(renderer.cleanups, 1, "Cleanup is complete when the call returns")
        }
        XCTAssertEqual(renderer.cleanups, 1, "Controller deinit must not repeat cleanup")

        let second = MetalViewController(renderer: renderer)
        _ = second.view
        defer { second.cleanup() }
        XCTAssertEqual(renderer.setups, 2)
        XCTAssertTrue(renderer.isSetup)
        XCTAssertTrue(second.metalView.delegate === renderer)
        XCTAssertTrue(renderer.metalView === second.metalView)
        XCTAssertTrue(renderer.lifecycleStayedOnMain)
    }
}
#endif
