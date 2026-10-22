#if os(macOS)

import Metal
@testable import Satin
import simd
import XCTest

/// Input a camera controller's handlers queued must not reach the camera once the controller is
/// disabled, which camera and view replacement do too, and must reach it while enabled.
final class CameraControllerLifecycleTests: XCTestCase {
    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private let frame = FrameTime.first(hostMediaTime: 0).next(time: 1.0 / 60.0, hostMediaTime: 1.0 / 60.0)

    func testQueuedInputReachesTheCameraOnUpdateWhileEnabled() throws {
        let camera = PerspectiveCamera(context: try makeContext())
        let controller = PerspectiveCameraController(camera: camera, view: MetalView())
        let before = controller.target.orientation

        controller.inputQueue.append(.begin(.rotating))
        controller.inputQueue.append(.rotate(axis: [0, 1, 0], angle: 0.5))
        XCTAssertEqual(controller.target.orientation, before, "handlers don't touch the camera")
        controller.update(frame: frame)

        XCTAssertNotEqual(controller.target.orientation, before)
    }

    func testDisablingDropsInputQueuedBeforeIt() throws {
        let camera = PerspectiveCamera(context: try makeContext())
        let controller = PerspectiveCameraController(camera: camera, view: MetalView())

        controller.inputQueue.append(.begin(.rotating))
        controller.inputQueue.append(.rotate(axis: [0, 1, 0], angle: 0.5))
        controller.disable()
        let orientation = camera.worldOrientation
        controller.update(frame: frame)

        XCTAssertEqual(camera.worldOrientation, orientation)
        XCTAssertEqual(controller.state, .inactive)
    }

    func testOrbitAndOrthographicControllersDropInputWhenDisabled() throws {
        let context = try makeContext()
        let orbit = OrbitPerspectiveCameraController(camera: PerspectiveCamera(context: context), view: MetalView())
        orbit.inputQueue.append(.beginRotation)
        orbit.inputQueue.append(.rotate([10, 10]))
        orbit.disable()
        orbit.update(frame: frame)
        XCTAssertEqual(orbit.state, .inactive)

        let orthographic = OrthographicCameraController(camera: OrthographicCamera(context: context), view: MetalView())
        orthographic.inputQueue.append(.begin(.panning))
        orthographic.inputQueue.append(.pan([0.5, 0.5]))
        orthographic.disable()
        let position = orthographic.camera.position
        orthographic.update(frame: frame)
        XCTAssertEqual(orthographic.camera.position, position)
        XCTAssertEqual(orthographic.state, .inactive)
    }
}

#endif
