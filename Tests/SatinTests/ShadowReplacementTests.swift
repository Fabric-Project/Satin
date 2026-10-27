@testable import Satin
import Metal
import simd
import XCTest

final class ShadowReplacementTests: XCTestCase {
    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func assertPosition(_ camera: Camera, equals position: simd_float3, file: StaticString = #filePath, line: UInt = #line) {
        for axis in 0 ..< 3 {
            XCTAssertEqual(camera.worldPosition[axis], position[axis], accuracy: 0.0001, file: file, line: line)
        }
    }

    func testStationaryPointLightAimsItsReplacementShadow() throws {
        let context = try makeContext()
        let light = PointLight(context: context, color: [1, 1, 1], radius: 23)
        light.position = [4, 5, 6]
        light.updateViewIfNeeded()
        let originalWorldRevision = light.worldRevision
        let originalLightRevision = light.lightRevision
        let replacement = PointShadow(context: context, label: "Replacement")

        light.shadow = replacement
        light.updateViewIfNeeded()

        assertPosition(replacement.camera, equals: light.worldPosition)
        XCTAssertEqual(replacement.camera.far, 23)
        XCTAssertEqual(replacement.matrices.count, 6)
        XCTAssertEqual(light.worldRevision, originalWorldRevision)
        XCTAssertEqual(light.lightRevision, originalLightRevision)
    }

    func testStationarySpotLightAimsItsReplacementShadow() throws {
        let context = try makeContext()
        let light = SpotLight(context: context, color: [1, 1, 1], radius: 17, angleOuter: 25)
        light.position = [-3, 2, 8]
        light.lookAt(target: [1, 0, 0])
        light.updateViewIfNeeded()
        let originalWorldRevision = light.worldRevision
        let replacement = SpotShadow(context: context, label: "Replacement")

        light.shadow = replacement
        light.updateViewIfNeeded()

        let camera = try XCTUnwrap(replacement.camera as? PerspectiveCamera)
        assertPosition(camera, equals: light.worldPosition)
        XCTAssertEqual(camera.far, 17)
        XCTAssertEqual(camera.fov, 50)
        for axis in 0 ..< 3 {
            XCTAssertEqual(camera.viewDirection[axis], light.worldForwardDirection[axis], accuracy: 0.0001)
        }
        XCTAssertEqual(light.worldRevision, originalWorldRevision)
    }
}
