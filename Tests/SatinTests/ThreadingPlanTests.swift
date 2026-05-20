@testable import Satin
import Metal
import XCTest

final class ThreadingPlanTests: XCTestCase {
    private final class TestRenderer: Renderer {
        var mode: MutationSchedulingMode = .immediate

        override var mutationSchedulingMode: MutationSchedulingMode { mode }

        func drainScheduledMutationsForTesting() {
            drainScheduledMutations()
        }
    }

    private func makeContext() -> Context? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float
        )
    }

    private func makeTexture(device: MTLDevice, size: Int = 4) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: descriptor)
    }

    private func makeMetalView(size: CGFloat = 256.0) -> MetalView {
        MetalView(frame: CGRect(x: 0.0, y: 0.0, width: size, height: size))
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

    func testIBLSceneAdoptsPendingTexturesDuringPrepareForRender() {
        guard let context = makeContext(),
              let cubemap = makeTexture(device: context.device),
              let irradiance = makeTexture(device: context.device),
              let reflection = makeTexture(device: context.device),
              let brdf = makeTexture(device: context.device)
        else { return }

        let scene = IBLScene(context: context)
        scene.stageEnvironmentTextures(
            generation: 0,
            cubemap: cubemap,
            irradiance: irradiance,
            reflection: reflection,
            brdf: brdf
        )

        XCTAssertNil(scene.cubemapTexture)
        scene.prepareForRender()

        XCTAssertTrue(scene.cubemapTexture === cubemap)
        XCTAssertTrue(scene.irradianceTexture === irradiance)
        XCTAssertTrue(scene.reflectionTexture === reflection)
        XCTAssertTrue(scene.brdfTexture === brdf)
    }

    func testIBLSceneRejectsStaleGenerationResults() {
        guard let context = makeContext(),
              let staleTexture = makeTexture(device: context.device),
              let freshTexture = makeTexture(device: context.device)
        else { return }

        let scene = IBLScene(context: context)
        let generation = scene.setPendingEnvironmentGenerationForTesting()
        scene.stageEnvironmentTextures(
            generation: generation - 1,
            cubemap: staleTexture,
            irradiance: nil,
            reflection: nil,
            brdf: nil
        )
        scene.prepareForRender()
        XCTAssertNil(scene.cubemapTexture)

        scene.stageEnvironmentTextures(
            generation: generation,
            cubemap: freshTexture,
            irradiance: nil,
            reflection: nil,
            brdf: nil
        )
        scene.prepareForRender()
        XCTAssertTrue(scene.cubemapTexture === freshTexture)
    }

    func testRendererScheduleExecutesImmediatelyInImmediateMode() {
        guard let context = makeContext() else { return }

        let renderer = TestRenderer(context: context)
        var value = 0

        renderer.schedule {
            value = 1
        }

        XCTAssertEqual(value, 1)
    }

    func testRendererScheduleDefersMutationsInQueuedModeUntilDrain() {
        guard let context = makeContext() else { return }

        let renderer = TestRenderer(context: context)
        renderer.mode = .queued
        var value = 0

        renderer.schedule {
            value = 1
        }

        XCTAssertEqual(value, 0)
        renderer.drainScheduledMutationsForTesting()
        XCTAssertEqual(value, 1)
    }

    func testPerspectiveCameraControllerOnlyAppliesQueuedInputDuringUpdate() {
        guard let context = makeContext() else { return }

        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 20.0, fov: 45.0)
        let controller = PerspectiveCameraController(camera: camera, view: makeMetalView())

        let originalZ = camera.position.z
        controller.queueZoomForTesting(0.5)

        XCTAssertEqual(camera.position.z, originalZ, accuracy: 0.0001)
        controller.update()
        XCTAssertNotEqual(camera.position.z, originalZ)
    }

    func testOrbitCameraControllerOnlyAppliesQueuedInputDuringUpdate() {
        guard let context = makeContext() else { return }

        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 20.0, fov: 45.0)
        let controller = OrbitPerspectiveCameraController(camera: camera, view: makeMetalView())

        let originalOrientation = controller.target.orientation
        controller.queueRotationForTesting([12.0, -8.0])

        XCTAssertTrue(simd_equal(controller.target.orientation.vector, originalOrientation.vector))
        controller.update()
        XCTAssertFalse(simd_equal(controller.target.orientation.vector, originalOrientation.vector))
    }

    func testOrthographicCameraControllerOnlyAppliesQueuedInputDuringUpdate() {
        guard let context = makeContext() else { return }

        let camera = OrthographicCamera(context: context, left: -1.0, right: 1.0, bottom: -1.0, top: 1.0, near: 0.1, far: 20.0)
        let controller = OrthographicCameraController(camera: camera, view: makeMetalView(), defaultZoom: 0.5)

        let originalPosition = camera.position
        controller.queuePanForTesting([0.25, -0.25])

        XCTAssertTrue(simd_equal(camera.position, originalPosition))
        controller.update()
        XCTAssertFalse(simd_equal(camera.position, originalPosition))
    }
}
