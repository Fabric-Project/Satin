@testable import Satin
import Metal
import simd
import XCTest

#if SWIFT_PACKAGE
import SatinCore
#endif

/// Culling skips a renderable only when its world bounds are wholly outside a pass's views, and a
/// point light's casters are recorded once for all six faces, each face encoding them as its own
/// view. Neither may change what is drawn.
final class CullingTests: XCTestCase {
    private var context: Context!
    private var commandQueue: MTLCommandQueue!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    // MARK: - Frustum

    private func box(center: simd_float3, halfSize: Float = 0.5) -> Bounds {
        Bounds(min: center - halfSize, max: center + halfSize)
    }

    private func frustum(of camera: Camera) -> ViewFrustum {
        ViewFrustum(viewProjectionMatrix: camera.viewProjectionMatrix)
    }

    func testAPerspectiveViewKeepsWhatIsInFrontAndCullsWhatIsBesideOrBehind() {
        let view = frustum(of: PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30))

        XCTAssertTrue(view.mayContain(box(center: .zero)))
        XCTAssertTrue(view.mayContain(box(center: [0, 0, -500])), "beyond the far plane is kept: near and far are never tested")
        XCTAssertFalse(view.mayContain(box(center: [100, 0, 0])), "wholly right of the view")
        XCTAssertFalse(view.mayContain(box(center: [0, -100, 0])), "wholly below it")
        XCTAssertFalse(view.mayContain(box(center: [0, 0, 20])), "wholly behind the eye")
        XCTAssertTrue(view.mayContain(box(center: [0, 0, 5], halfSize: 1)), "around the eye")
    }

    func testAnOrthographicViewCullsOnlyBesideIt() {
        let camera = OrthographicCamera(context: context, left: -1, right: 1, bottom: -1, top: 1, near: 0.1, far: 10)
        camera.position = [0, 0, 5]
        let view = frustum(of: camera)

        XCTAssertTrue(view.mayContain(box(center: [0.9, 0, 0], halfSize: 0.2)), "straddling the right side")
        XCTAssertFalse(view.mayContain(box(center: [3, 0, 0], halfSize: 0.2)))
    }

    func testBoundsThatCantBeJudgedAreNeverCulled() {
        let view = frustum(of: PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30))

        XCTAssertTrue(view.mayContain(createBounds()), "empty")
        XCTAssertTrue(view.mayContain(Bounds(min: [100, 0, 0], max: [.infinity, 1, 1])), "infinite")
        XCTAssertTrue(view.mayContain(Bounds(min: [100, .nan, 0], max: [101, 1, 1])), "not a number")
    }

    // MARK: - Colour

    private func makeMesh(at position: simd_float3) -> Mesh {
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
        mesh.position = position
        mesh.update()
        return mesh
    }

    /// The packets `mesh` records into a submission seen from [0, 0, 5] looking down -z.
    private func recordedPacketCount(_ mesh: Mesh) throws -> Int {
        let encoder = RenderEncoder(context: context)
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [MTLViewport(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
        try submission.record(scene: Object(context: context, label: "Scene", [mesh]))
        return submission.recorder.storage.runs.reduce(0) { $0 + $1.packets.count }
    }

    func testAColourPassSkipsARenderableOutsideItsViews() throws {
        XCTAssertGreaterThan(try recordedPacketCount(makeMesh(at: .zero)), 0)
        XCTAssertEqual(try recordedPacketCount(makeMesh(at: [100, 0, 0])), 0)
    }

    func testARenderableThatIsNotFrustumCulledIsAlwaysRecorded() throws {
        let mesh = makeMesh(at: [100, 0, 0])
        mesh.frustumCulled = false
        XCTAssertGreaterThan(try recordedPacketCount(mesh), 0)
    }

    // MARK: - Point Shadows

    /// Draws `scene` once, seen from [0, 0, 5].
    private func draw(_ scene: Object) throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 16, height: 16, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        let target = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        try encoder.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, scene: scene, camera: camera, renderTarget: target)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func makePointLightScene(caster: Mesh) -> Object {
        let light = PointLight(context: context, color: [1, 1, 1], intensity: 10, radius: 20)
        light.castShadow = true
        let floor = Mesh(context: context, label: "Floor", geometry: PlaneGeometry(context: context, size: 10, orientation: .zx), material: BasicDiffuseMaterial(context: context))
        floor.position.y = -2
        floor.receiveShadow = true
        caster.castShadow = true
        return Object(context: context, label: "Scene", [light, floor, caster])
    }

    func testSeparatelyEncodedViewsEachStartOnA256ByteBoundary() throws {
        XCTAssertEqual(PacketRecorder.viewSlotStride % 256, 0)
        XCTAssertGreaterThanOrEqual(PacketRecorder.viewSlotStride, PacketRecorder.vertexUniformsStride)

        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: FrameArena(device: context.device).lease(frame: .zero))
        let mesh = makeMesh(at: .zero)
        mesh.beginOccurrence(frame: .zero)
        let cameras = [
            PerspectiveCamera(context: context, position: [-1, 0, 5], near: 0.1, far: 100, fov: 30),
            PerspectiveCamera(context: context, position: [1, 0, 5], near: 0.1, far: 100, fov: 30),
            PerspectiveCamera(context: context, position: [0, 1, 5], near: 0.1, far: 100, fov: 30),
        ]

        let packets = try recorder.record(mesh, renderContext: context, pass: .color, materialPass: .all, views: cameras.map { RenderView(camera: $0, viewport: [0, 0, 64, 64]) })

        XCTAssertFalse(packets.isEmpty)
        let packet = storage.packets[packets.lowerBound]
        let binding = storage.commands[Int(packet.commandStart) ..< Int(packet.commandStart + packet.commandCount)].compactMap { command -> (bufferIndex: Int32, offset: Int)? in
            if case let .perViewVertexBuffer(bufferIndex, offset, .VertexUniforms) = command { return (bufferIndex, offset) }
            return nil
        }.first
        let vertexUniforms = try XCTUnwrap(binding)
        XCTAssertEqual(vertexUniforms.offset % 256, 0)
        storage.writeVertexUniforms()
        let contents = storage.buffers[Int(vertexUniforms.bufferIndex)].contents() + vertexUniforms.offset
        // viewMatrix follows modelMatrix in each view's VertexUniforms.
        for (view, camera) in cameras.enumerated() {
            let viewMatrix = (contents + view * PacketRecorder.viewSlotStride + MemoryLayout<simd_float4x4>.stride).load(as: simd_float4x4.self)
            XCTAssertEqual(viewMatrix, camera.viewMatrix, "view \(view) sits at its own aligned slot")
        }
    }

    func testAPointLightRecordsEachCasterOnceForAllItsFaces() throws {
        let caster = DrawCountingMesh(context: context, geometry: BoxGeometry(context: context), material: BasicDiffuseMaterial(context: context))
        caster.position = [0, -1, 0]

        try draw(makePointLightScene(caster: caster))

        XCTAssertEqual(caster.shadowDraws, 1, "one recording serves every face it reaches")
    }

    func testEveryShadowOfAFrameSharesOneRecordingOfACaster() throws {
        let caster = DrawCountingMesh(context: context, geometry: BoxGeometry(context: context), material: BasicDiffuseMaterial(context: context))
        caster.frustumCulled = false
        let scene = makePointLightScene(caster: caster)
        let secondPoint = PointLight(context: context, color: [1, 1, 1], intensity: 10, radius: 20)
        secondPoint.position = [3, 0, 0]
        secondPoint.castShadow = true
        let spot = SpotLight(context: context, color: [1, 1, 1], intensity: 10, radius: 20, angleInner: 10, angleOuter: 30)
        spot.position = [0, 4, 0]
        spot.castShadow = true
        scene.add(secondPoint)
        scene.add(spot)

        try draw(scene)

        XCTAssertEqual(caster.shadowDraws, 1, "two point lights' twelve faces and a spot light encode one recording")
    }

    func testAPointLightSkipsACasterBeyondItsReach() throws {
        let caster = DrawCountingMesh(context: context, geometry: BoxGeometry(context: context), material: BasicDiffuseMaterial(context: context))
        caster.position = [0, 0, -50]

        try draw(makePointLightScene(caster: caster))

        XCTAssertEqual(caster.shadowDraws, 0, "outside every face's far plane")
    }

    /// A point-shadowed scene whose caster is recorded once for every face casts its shadow.
    func testACasterRecordedOnceForEveryFaceCastsItsShadow() throws {
        func render(castsShadow: Bool) throws -> RGBAImage {
            try VisualTestHarness.render(size: [96, 96]) { renderer, camera in
                let context = renderer.context
                let light = PointLight(context: context, color: [1, 1, 1], intensity: 6, radius: 30)
                light.position = [0.5, 2.5, 0.5]
                light.castShadow = true
                light.shadow.resolution = (width: 256, height: 256)
                let floor = Mesh(context: context, label: "Floor", geometry: PlaneGeometry(context: context, size: 8, orientation: .zx), material: StandardMaterial(context: context))
                floor.position.y = -1.0
                floor.receiveShadow = true
                let caster = DrawCountingMesh(context: context, geometry: BoxGeometry(context: context), material: StandardMaterial(context: context))
                caster.castShadow = castsShadow
                return (scene: Object(context: context, label: "Scene", [light, floor, caster]), camera: camera)
            }
        }

        let shadowed = try render(castsShadow: true)
        let unshadowed = try render(castsShadow: false)

        XCTAssertNotEqual(shadowed.pixels, unshadowed.pixels, "each face encodes the shared recording as its own view")
    }
}

/// Counts its shadow-pass recordings.
private final class DrawCountingMesh: Mesh {
    var shadowDraws = 0

    override func draw(in context: RenderableDrawContext) throws {
        if context.pass == .shadow {
            shadowDraws += 1
        }
        try super.draw(in: context)
    }
}
