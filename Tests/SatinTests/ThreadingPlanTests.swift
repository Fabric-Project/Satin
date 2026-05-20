@testable import Satin
import Metal
import XCTest

final class ThreadingPlanTests: XCTestCase {
    private func makeContext() -> Context? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float
        )
    }

    private func runFrame(renderer: RenderEncoder, scene: Object, camera: Camera, size: SIMD2<Int> = .init(32, 32)) throws {
        guard let commandQueue = renderer.context.device.makeCommandQueue() else {
            XCTFail("Failed to create command queue")
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: renderer.context.colorPixelFormat,
            width: size.x,
            height: size.y,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        guard let outputTexture = renderer.context.device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            XCTFail("Failed to create rendering resources")
            return
        }

        renderer.resize((Float(size.x), Float(size.y)))
        renderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            renderTarget: outputTexture
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
    }

    func testRenderSnapshotRunsAfterObjectUpdate() throws {
        guard let context = makeContext() else { return }

        final class MutatingObject: Object {
            override func update() {
                super.update()
                position = [1.0, 2.0, 3.0]
            }
        }

        let scene = MutatingObject(context: context, label: "Scene")
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 20.0, fov: 45.0)
        let renderer = RenderEncoder(context: context)

        try runFrame(renderer: renderer, scene: scene, camera: camera)

        XCTAssertEqual(scene.renderWorldPosition.x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(scene.renderWorldPosition.y, 2.0, accuracy: 0.0001)
        XCTAssertEqual(scene.renderWorldPosition.z, 3.0, accuracy: 0.0001)
    }

    func testScheduledMutationsDrainBeforeTraversal() throws {
        guard let context = makeContext() else { return }

        let scene = Object(context: context, label: "Scene")
        let child = Object(context: context, label: "Child")
        child.position = [0.5, 0.0, 0.0]

        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 20.0, fov: 45.0)
        let renderer = RenderEncoder(context: context)
        renderer.schedule {
            scene.add(child)
        }

        try runFrame(renderer: renderer, scene: scene, camera: camera)

        XCTAssertEqual(scene.children.count, 1)
        XCTAssertTrue(scene.children.first === child)
        XCTAssertEqual(child.renderWorldPosition.x, 0.5, accuracy: 0.0001)
    }

    func testCameraRefreshRenderStateProducesStableMatrices() {
        guard let context = makeContext() else { return }

        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 20.0, fov: 45.0)
        camera.lookAt(target: .zero)
        camera.refreshRenderState()

        let expectedViewProjection = camera.renderProjectionMatrix * camera.renderViewMatrix
        XCTAssertTrue(simd_equal(camera.renderWorldPosition, simd_float3(0.0, 0.0, 5.0)))
        XCTAssertTrue(simd_almost_equal_elements(camera.renderViewProjectionMatrix, expectedViewProjection, 0.0001))
    }
}
