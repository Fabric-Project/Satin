@testable import Satin
import Foundation
import Metal
import MetalPerformanceShaders
import XCTest

final class RendererSegmentLifetimeTests: XCTestCase {
    func testFramePermitSurvivesAnIntermediateMPSCommit() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                              depthPixelFormat: .invalid, stencilPixelFormat: .invalid)
        let renderer = Renderer(context: context)
        var pending: [MTLCommandBuffer] = []
        for _ in 0..<Satin.maxBuffersInFlight {
            pending.append(try XCTUnwrap(renderer.preDraw()))
        }
        let first = MPSCommandBuffer(commandBuffer: pending.removeFirst())
        let submitted = first.rootCommandBuffer
        first.commitAndContinue()
        submitted.waitUntilCompleted()

        let requesting = DispatchSemaphore(value: 0)
        let admitted = DispatchSemaphore(value: 0)
        DispatchQueue(label: "Satin.FramePermitTest").async {
            requesting.signal()
            if let next = renderer.preDraw() { renderer.postDraw(commandBuffer: next) }
            admitted.signal()
        }
        XCTAssertEqual(requesting.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(admitted.wait(timeout: .now() + 0.1), .timedOut,
                       "An intermediate segment must not release the logical frame's slot")
        renderer.postDraw(commandBuffer: first)
        XCTAssertEqual(admitted.wait(timeout: .now() + 2), .success)
        for commandBuffer in pending { renderer.postDraw(commandBuffer: commandBuffer) }
        for commandBuffer in pending { commandBuffer.waitUntilCompleted() }
        first.waitUntilCompleted()
    }
}
