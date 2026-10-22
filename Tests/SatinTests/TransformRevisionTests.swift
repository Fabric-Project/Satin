@testable import Satin
import Metal
import simd
import XCTest

/// Transforms are invalidated by revisions, not pushed: a change bumps its object's local revision,
/// and world-derived values (world matrices, world bounds, camera views, light uploads, instance
/// uniforms) validate against their ancestors when read. Descendant changes still mark ancestor
/// bounds dirty. The public update lifecycle is unchanged.
final class TransformRevisionTests: XCTestCase {
    private var context: Context!
    private var commandQueue: MTLCommandQueue!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func assertEqual(_ a: simd_float3, _ b: simd_float3, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-4, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-4, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: 1e-4, message, file: file, line: line)
    }

    private func assertEqual(_ a: simd_float4x4, _ b: simd_float4x4, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        for column in 0 ..< 4 {
            for row in 0 ..< 4 {
                XCTAssertEqual(a[column][row], b[column][row], accuracy: 1e-4, message, file: file, line: line)
            }
        }
    }

    private func makeBox() -> Mesh {
        Mesh(context: context, geometry: BoxGeometry(context: context, size: 1), material: BasicColorMaterial(context: context))
    }

    // MARK: - Transforms

    func testAParentsMoveReachesAGrandchildOnItsNextRead() {
        let grandchild = Object(context: context, label: "Grandchild")
        let child = Object(context: context, label: "Child", [grandchild])
        let parent = Object(context: context, label: "Parent", [child])
        _ = grandchild.worldMatrix

        parent.position = [2, 0, 0]

        assertEqual(grandchild.worldPosition, [2, 0, 0])
        assertEqual(simd_make_float3(grandchild.worldMatrix.columns.3), [2, 0, 0])
    }

    func testReadingOnlyARevisionSeesAnAncestorsMove() {
        let child = Object(context: context, label: "Child")
        let parent = Object(context: context, label: "Parent", [child])
        let before = child.worldRevision

        parent.position = [1, 0, 0]

        XCTAssertNotEqual(child.worldRevision, before, "reading the revision validates against the parent, with no matrix read first")
    }

    func testReparentingBetweenParentsWithEqualRevisionsRecomputesTheWorldMatrix() {
        let first = Object(context: context, label: "First")
        let second = Object(context: context, label: "Second")
        first.position = [1, 0, 0]
        second.position = [5, 0, 0]
        XCTAssertEqual(first.worldRevision, second.worldRevision, "set up: equal revisions")
        let child = Object(context: context, label: "Child")
        first.add(child)
        assertEqual(child.worldPosition, [1, 0, 0])

        second.add(child)

        assertEqual(child.worldPosition, [5, 0, 0], "the parent's identity is part of what the world matrix depends on")
    }

    func testDetachingMakesTheLocalMatrixTheWorldMatrix() {
        let child = Object(context: context, label: "Child")
        let parent = Object(context: context, label: "Parent", [child])
        parent.position = [3, 0, 0]
        child.position = [1, 0, 0]
        assertEqual(child.worldPosition, [4, 0, 0])

        parent.remove(child)

        assertEqual(child.worldPosition, [1, 0, 0])
    }

    func testAssigningTheLocalMatrixBumpsTheLocalRevisionOnce() {
        let object = Object(context: context, label: "Object")
        let before = object.localRevision
        let matrix = simd_float4x4(translation: [1, 2, 3]) * simd_float4x4(simd_quatf(angle: 0.5, axis: [0, 1, 0])) * simd_float4x4(scale: [2, 2, 2])

        object.localMatrix = matrix

        XCTAssertEqual(object.localRevision, before &+ 1)
        assertEqual(object.localMatrix, matrix)
    }

    func testEqualValueAssignmentsChangeNothing() {
        let object = Object(context: context, label: "Object")
        object.position = [1, 2, 3]
        let local = object.localRevision
        let epoch = Object.transformEpoch.load(ordering: .relaxed)

        object.position = [1, 2, 3]
        object.scale = .one
        object.orientation = simd_quatf(matrix_identity_float4x4)

        XCTAssertEqual(object.localRevision, local)
        XCTAssertEqual(Object.transformEpoch.load(ordering: .relaxed), epoch)
    }

    #if DEBUG
    func testAnUnchangedSceneReadsWorldMatricesWithoutWalkingAncestors() {
        let leaf = Object(context: context, label: "Leaf")
        let middle = Object(context: context, label: "Middle", [leaf])
        let root = Object(context: context, label: "Root", [middle])
        root.position = [1, 0, 0]
        // Per object, and only while the process-wide epoch holds: anything moving elsewhere in
        // the process moves the epoch, which correctly costs one walk.
        let epoch = Object.transformEpoch.load(ordering: .relaxed)
        _ = leaf.worldMatrix
        let walks = leaf.worldValidationWalkCount + middle.worldValidationWalkCount + root.worldValidationWalkCount

        for _ in 0 ..< 10 { _ = leaf.worldMatrix }

        if Object.transformEpoch.load(ordering: .relaxed) == epoch {
            XCTAssertEqual(leaf.worldValidationWalkCount + middle.worldValidationWalkCount + root.worldValidationWalkCount, walks,
                           "nothing moved, so validation returns at once")
        }
    }
    #endif

    // MARK: - Bounds

    func testAChildsMoveReachesItsParentsBoundsOnTheNextRead() {
        let child = makeBox()
        let parent = Object(context: context, label: "Parent", [child])
        XCTAssertEqual(parent.worldBounds.max.x, 0.5, accuracy: 1e-4)

        child.position = [2, 0, 0]

        XCTAssertEqual(parent.worldBounds.max.x, 2.5, accuracy: 1e-4, "descendant changes still mark ancestor bounds")
    }

    func testAGrandparentsMoveReachesAGrandchildsBounds() {
        let grandchild = makeBox()
        let grandparent = Object(context: context, label: "Grandparent", [Object(context: context, label: "Parent", [grandchild])])
        XCTAssertEqual(grandchild.worldBounds.max.x, 0.5, accuracy: 1e-4)

        grandparent.position = [3, 0, 0]

        XCTAssertEqual(grandchild.worldBounds.max.x, 3.5, accuracy: 1e-4, "ancestor moves are seen by revision")
        XCTAssertEqual(grandparent.worldBounds.max.x, 3.5, accuracy: 1e-4, "and the moved ancestor's own bounds, which merge its children's")
    }

    func testAChildsGeometryChangeReachesItsParentsBounds() {
        let geometry = BoxGeometry(context: context, size: 1)
        let child = Mesh(context: context, geometry: geometry, material: BasicColorMaterial(context: context))
        let parent = Object(context: context, label: "Parent", [child])
        XCTAssertEqual(parent.worldBounds.max.x, 0.5, accuracy: 1e-4)

        geometry.size = [4, 4, 4]
        geometry.update()

        XCTAssertEqual(parent.worldBounds.max.x, 2, accuracy: 1e-4)
    }

    // MARK: - Cameras

    func testACameraUnderAMovingParentHasACurrentView() {
        let camera = PerspectiveCamera(context: context, position: .zero, near: 0.1, far: 100)
        let rig = Object(context: context, label: "Rig", [camera])
        _ = camera.viewProjectionMatrix

        rig.position = [0, 0, 5]

        assertEqual(camera.viewMatrix, camera.worldMatrix.inverse)
        assertEqual(camera.viewProjectionMatrix, camera.projectionMatrix * camera.worldMatrix.inverse)
        assertEqual(camera.viewDirection, [0, 0, -1])
    }

    func testProjectionInputsReachTheProjection() {
        let perspective = PerspectiveCamera(context: context, position: .zero, near: 0.1, far: 100, fov: 45)
        let before = perspective.projectionMatrix
        perspective.fov = 60
        XCTAssertNotEqual(perspective.projectionMatrix.columns.1.y, before.columns.1.y)
        perspective.near = 1
        assertEqual(perspective.projectionMatrix, perspectiveMatrixf(60, perspective.aspect, 1, 100))

        let orthographic = OrthographicCamera(context: context, left: -1, right: 1, bottom: -1, top: 1, near: 0, far: 10)
        orthographic.right = 3
        assertEqual(orthographic.projectionMatrix, orthographicMatrixf(-1, 3, -1, 1, 0, 10))
    }

    func testAnAssignedProjectionHoldsUntilAProjectionInputChanges() {
        let camera = PerspectiveCamera(context: context, position: .zero, near: 0.1, far: 100)
        var assigned = perspectiveMatrixf(50, 1.5, 0.5, 20)
        assigned.columns.2.x = 0.1 // something the inputs can't express

        camera.projectionMatrix = assigned
        _ = camera.projectionMatrix
        camera.position = [1, 0, 0]

        assertEqual(camera.projectionMatrix, assigned, "repeated reads and a move keep the assigned matrix")
        camera.fov = 70
        XCTAssertNotEqual(camera.projectionMatrix.columns.2.x, 0.1, accuracy: 1e-6, "a later input change rebuilds it")
    }

    func testAnARKitProjectionHoldsUntilAProjectionInputChanges() {
        let camera = PerspectiveCamera(context: context, position: .zero, near: 0.1, far: 100)
        var arkit = perspectiveMatrixf(55, 0.75, 0.1, 100)
        arkit.columns.2.x = 0.05

        camera.setProjectionMatrixFromARKit(arkit)
        let assigned = camera.projectionMatrix
        _ = camera.viewProjectionMatrix

        assertEqual(camera.projectionMatrix, assigned, "the ARKit matrix survives reads")
        camera.near = 0.5
        XCTAssertNotEqual(camera.projectionMatrix.columns.3.z, assigned.columns.3.z, accuracy: 1e-6, "and is rebuilt after an input change")
    }

    func testAnAssignedViewHoldsUntilTheCameraMoves() {
        let camera = PerspectiveCamera(context: context, position: .zero, near: 0.1, far: 100)
        let view = simd_float4x4(translation: [0.1, 0.2, -3])

        camera.viewMatrix = view

        assertEqual(camera.viewMatrix, view)
        camera.position = [0, 0, 9]
        assertEqual(camera.viewMatrix, camera.worldMatrix.inverse, "a later move replaces it")
    }

    // MARK: - Lifecycle

    private func makeTarget() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 16, height: 16, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        return try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
    }

    /// Draws `scene` `frames` times with one encoder.
    private func draw(_ encoder: RenderEncoder, _ scene: Object, frames: Int = 1) throws {
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100)
        let target = try makeTarget()
        var frame = FrameTime.zero
        for index in 0 ..< frames {
            if index > 0 { frame = frame.next(time: Double(index) / 60) }
            let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
            try encoder.draw(frame: frame, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, scene: scene, camera: camera, renderTarget: target)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }

    func testUpdateAndOnUpdateStillRunEveryFrame() throws {
        let object = makeBox()
        var updates = 0
        object.onUpdate = { updates += 1 }
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))

        try draw(encoder, Object(context: context, label: "Scene", [object]), frames: 3)

        XCTAssertEqual(updates, 3, "unchanged objects still get their update every frame")
    }

    func testAnInstancedMeshMovedByItsParentRebuildsItsInstanceUniforms() {
        let instanced = InstancedMesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context), count: 1)
        let parent = Object(context: context, label: "Parent", [instanced])
        instanced.setMatrixAt(index: 0, matrix: matrix_identity_float4x4)
        instanced.update()

        parent.position = [2, 0, 0]
        instanced.update()

        assertEqual(simd_make_float3(instanced.instanceMatricesUniforms[0].modelMatrix.columns.3), [2, 0, 0])
    }

    // MARK: - Lights

    func testALightMovedByItsParentHasCurrentShadowCamerasAfterADraw() throws {
        let light = PointLight(context: context, color: .one, radius: 10)
        light.castShadow = true
        let holder = Object(context: context, label: "Holder", [light])
        let caster = makeBox()
        caster.castShadow = true
        caster.receiveShadow = true
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let scene = Object(context: context, label: "Scene", [holder, caster])
        try draw(encoder, scene)

        holder.position = [0, 5, 0]
        holder.orientation = simd_quatf(angle: 0.5, axis: [0, 1, 0])
        try draw(encoder, scene)

        assertEqual(light.shadow.camera.worldPosition, light.worldPosition)
        assertEqual(simd_make_float3(encoder.uploadedLightData[0].position), light.worldPosition, "and uploads its new position")
    }

    func testReplacingALightAtTheSameCountUploadsTheNewOne() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let scene = Object(context: context, label: "Scene", [makeBox()])
        let first = PointLight(context: context, color: [1, 0, 0])
        scene.add(first)
        try draw(encoder, scene)

        scene.remove(first)
        scene.add(PointLight(context: context, color: [0, 0, 1]))
        try draw(encoder, scene)

        XCTAssertEqual(encoder.uploadedLightData[0].color.z, 1, accuracy: 1e-5)
        XCTAssertEqual(encoder.uploadedLightData[0].color.x, 0, accuracy: 1e-5)
    }

    func testReorderingLightsUploadsThemInTheNewOrder() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let red = PointLight(context: context, color: [1, 0, 0])
        let blue = PointLight(context: context, color: [0, 0, 1])
        let scene = Object(context: context, label: "Scene", [makeBox(), red, blue])
        try draw(encoder, scene)

        scene.children = [scene.children[0], blue, red]
        try draw(encoder, scene)

        XCTAssertEqual(encoder.uploadedLightData[0].color.z, 1, accuracy: 1e-5, "blue first now")
        XCTAssertEqual(encoder.uploadedLightData[1].color.x, 1, accuracy: 1e-5)
    }

    func testTogglingShadowParticipationReuploadsTheShadowIndex() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let caster = makeBox()
        caster.castShadow = true
        caster.receiveShadow = true
        let light = DirectionalLight(context: context, color: .one, intensity: 1)
        let scene = Object(context: context, label: "Scene", [caster, light])
        try draw(encoder, scene)
        XCTAssertEqual(encoder.uploadedLightData[0].shadowInfo.x, -1, "no shadow yet")

        light.castShadow = true
        // The shadow map is made by the first shadow pass, after indices are assigned that frame.
        try draw(encoder, scene, frames: 2)

        XCTAssertEqual(encoder.uploadedLightData[0].shadowInfo.x, 0, "the renderer-assigned shadow index is uploaded without the light moving")
    }

    func testColorChangesUploadAndUnchangedLightsDoNot() throws {
        let encoder = RenderEncoder(context: context)
        encoder.resize((width: 16, height: 16))
        let light = PointLight(context: context, color: [1, 0, 0])
        let scene = Object(context: context, label: "Scene", [makeBox(), light])
        try draw(encoder, scene)
        let uploads = encoder.lightDataUploadCount

        try draw(encoder, scene, frames: 3)
        XCTAssertEqual(encoder.lightDataUploadCount, uploads, "nothing changed, nothing uploaded")

        light.color = [0, 1, 0]
        try draw(encoder, scene)
        XCTAssertEqual(encoder.lightDataUploadCount, uploads + 1)
        XCTAssertEqual(encoder.uploadedLightData[0].color.y, 1, accuracy: 1e-5)
    }

    func testASpotLightsProjectorIsCurrentWhenRead() {
        let light = SpotLight(context: context, color: .one, radius: 10)
        _ = light.projectorMatrix

        // Off the vertical: the projector aims with world up, which a straight-down light can't use.
        light.position = [0, 2, 3]
        light.lookAt(target: .zero)
        let expected = PerspectiveCamera(context: context, position: light.worldPosition, near: 0.01, far: 10, fov: light.angleOuter * 2)
        expected.lookAt(target: light.worldPosition + light.worldForwardDirection, up: Satin.worldUpDirection)
        expected.aspect = 1

        assertEqual(light.projectorMatrix, expected.viewProjectionMatrix)
    }
}
