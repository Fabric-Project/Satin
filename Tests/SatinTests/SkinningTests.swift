import Metal
import Satin
import simd
import XCTest

/// GPU skinning: a geometry with `JointIndices`, `JointWeights` and a `JointPalette` moves its
/// vertices on the GPU through the standard materials, and nothing changes for geometry
/// without them.
final class SkinningTests: XCTestCase {
    /// The right side of the frame, where the unskinned bar never reaches.
    private let rightOfBar = CGRect(x: 0.62, y: 0.05, width: 0.3, height: 0.9)

    func testIdentityPaletteMatchesUnskinned() throws {
        let unskinned = try renderBar(skinned: false, palette: nil) { NormalColorMaterial(context: $0) }
        let skinned = try renderBar(skinned: true, palette: [matrix_identity_float4x4, matrix_identity_float4x4]) { NormalColorMaterial(context: $0) }
        XCTAssertEqual(unskinned.pixels, skinned.pixels, "An identity pose must render exactly like the rest pose")
    }

    func testJointAttributesWithoutPaletteRenderUnskinned() throws {
        let plain = try renderBar(skinned: false, palette: nil) { BasicColorMaterial(context: $0) }
        let attributesOnly = try renderBar(skinned: true, palette: nil) { BasicColorMaterial(context: $0) }
        XCTAssertEqual(plain.pixels, attributesOnly.pixels, "Joint attributes alone must not change rendering")
    }

    func testPaletteMovesWeightedVertices() throws {
        let rest = try renderBar(skinned: false, palette: nil) { BasicColorMaterial(context: $0) }
        let shifted = matrix_float4x4(columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(1.0, 0, 0, 1)
        ))
        // Joint 1 (the bar's upper half) moves right by one unit; joint 0 stays.
        let posed = try renderBar(skinned: true, palette: [matrix_identity_float4x4, shifted]) { BasicColorMaterial(context: $0) }

        XCTAssertLessThan(VisualTestHarness.contentCoverage(rest, in: rightOfBar).changedPixelRatio, 0.001,
                          "The rest pose should leave the right side empty")
        VisualTestHarness.assertContainsVisibleContent(
            posed,
            in: ImageRegion(name: "right of bar", normalizedRect: rightOfBar),
            minimumChangedPixelRatio: 0.03
        )
    }

    func testIdentityPaletteMatchesUnskinnedLitAndShadowed() throws {
        let materials: [(name: String, make: (Context) -> Material)] = [
            ("Standard", { StandardMaterial(context: $0) }),
            ("Physical", { PhysicalMaterial(context: $0) }),
            ("BasicDiffuse", { BasicDiffuseMaterial(context: $0) }),
        ]
        for material in materials {
            let unskinned = try renderBar(skinned: false, palette: nil, lit: true, material: material.make)
            let skinned = try renderBar(skinned: true, palette: [matrix_identity_float4x4, matrix_identity_float4x4], lit: true, material: material.make)
            XCTAssertEqual(unskinned.pixels, skinned.pixels, "\(material.name): an identity pose must render and shadow exactly like the rest pose")
        }
    }

    func testPaletteMovesLitGeometry() throws {
        let shifted = matrix_float4x4(columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(1.0, 0, 0, 1)
        ))
        let rest = try renderBar(skinned: false, palette: nil, lit: true) { StandardMaterial(context: $0) }
        let posed = try renderBar(skinned: true, palette: [matrix_identity_float4x4, shifted], lit: true) { StandardMaterial(context: $0) }
        XCTAssertNotEqual(rest.pixels, posed.pixels)
        VisualTestHarness.assertContainsVisibleContent(
            posed,
            in: ImageRegion(name: "right of bar", normalizedRect: CGRect(x: 0.62, y: 0.05, width: 0.3, height: 0.6)),
            minimumChangedPixelRatio: 0.02
        )
    }

    // MARK: - Instancing

    func testInstancedSkinnedMatchesSeparateMeshes() throws {
        let offsets: [Float] = [-0.9, 0.0, 0.9]
        let pose = [matrix_identity_float4x4, translation(x: 0.25)]
        let separate = try VisualTestHarness.render(size: [160, 160]) { renderer, camera in
            let context = renderer.context
            let geometry = makeSkinnedBar(context: context, pose: pose)
            let scene = Object(context: context, label: "Scene")
            for offset in offsets {
                let mesh = Mesh(context: context, label: "Bar", geometry: geometry, material: NormalColorMaterial(context: context))
                mesh.cullMode = .none
                mesh.position.x = offset
                scene.add(mesh)
            }
            return (scene: scene, camera: camera)
        }
        let instanced = try VisualTestHarness.render(size: [160, 160]) { renderer, camera in
            let context = renderer.context
            let geometry = makeSkinnedBar(context: context, pose: pose)
            let mesh = InstancedMesh(context: context, label: "Bars", geometry: geometry, material: NormalColorMaterial(context: context), count: offsets.count)
            mesh.cullMode = .none
            mesh.setInstanceMatrices(offsets.map { translation(x: $0) })
            return (scene: Object(context: context, label: "Scene", [mesh]), camera: camera)
        }
        // Instancing multiplies the matrices in a different order, so allow edge-pixel rounding.
        XCTAssertLessThan(differingPixelRatio(separate, instanced), 0.005, "Each instance must skin, then take its own transform")
        VisualTestHarness.assertContainsVisibleContent(instanced, minimumChangedPixelRatio: 0.03)
    }

    // MARK: - Velocity

    func testStillPoseVelocityMatchesUnskinned() throws {
        let unskinned = try renderBarVelocity(previousPose: nil, currentPose: nil)
        let still = try renderBarVelocity(previousPose: [matrix_identity_float4x4, matrix_identity_float4x4],
                                          currentPose: [matrix_identity_float4x4, matrix_identity_float4x4])
        XCTAssertEqual(unskinned, still, "A pose that has not moved adds no velocity")
        XCTAssertTrue(unskinned.contains { $0 != 0 }, "The bar must draw into the velocity target")
    }

    func testPreviousPoseDrivesVelocity() throws {
        let shifted = [matrix_identity_float4x4, translation(x: 0.5)]
        // Same current pose in both; only the pose they came from differs.
        let settled = try renderBarVelocity(previousPose: shifted, currentPose: shifted)
        let moving = try renderBarVelocity(previousPose: [matrix_identity_float4x4, matrix_identity_float4x4], currentPose: shifted)
        let differing = zip(settled, moving).filter { $0 != $1 }.count
        XCTAssertGreaterThan(Double(differing) / Double(settled.count), 0.01, "Motion between poses must reach the velocity output")
    }

    func testInstanceMotionReachesVelocityAndSettles() throws {
        let offsets: [Float] = [-0.9, 0.0, 0.9]
        var instanced: InstancedMesh?
        let frames = try renderVelocityFrames(frameCount: 4) { context in
            let mesh = InstancedMesh(context: context, label: "Bars", geometry: makeBarGeometry(context: context, withJoints: false),
                                     material: VelocityMaterial(context: context), count: offsets.count)
            mesh.cullMode = .none
            mesh.setInstanceMatrices(offsets.map { translation(x: $0) })
            instanced = mesh
            return Object(context: context, label: "Scene", [mesh])
        } beforeFrame: { frame in
            // Frame 2 moves the middle instance; frame 3 holds it there.
            if frame == 2 { instanced?.setMatrixAt(index: 1, matrix: translation(x: 0.3)) }
        }
        // Frame 0 has no real previous camera; frame 1 is still; frame 2 moves; frame 3 is still again.
        // The sign bit is masked: the shader negates y, so zero velocity can read as -0.
        XCTAssertFalse(frames[1].contains { $0 & 0x7FFF != 0 }, "Still instances under a still camera write zero velocity")
        XCTAssertTrue(frames[2].contains { $0 & 0x7FFF != 0 }, "A moved instance writes velocity")
        XCTAssertFalse(frames[3].contains { $0 & 0x7FFF != 0 }, "Velocity returns to zero once the instance stops")
    }

    func testSwappingInSkinnedGeometryUnderExistingMaterialSkins() throws {
        // Fabric's Mesh node keeps its material and swaps geometry when its input changes.
        var mesh: Mesh?
        var posedGeometry: Geometry?
        let frames = try renderVelocityFrames(frameCount: 2) { context in
            posedGeometry = makeSkinnedBar(context: context, pose: [matrix_identity_float4x4, translation(x: 1.0)])
            let bar = Mesh(context: context, label: "Bar", geometry: makeBarGeometry(context: context, withJoints: false),
                           material: BasicColorMaterial(context: context))
            bar.cullMode = .none
            mesh = bar
            return Object(context: context, label: "Scene", [bar])
        } beforeFrame: { frame in
            if frame == 1, let posedGeometry { mesh?.geometry = posedGeometry }
        }
        // The right quarter of the frame: empty at rest, covered once the upper half shifts right.
        XCTAssertFalse(hasContent(frames[0], inColumnsFrom: 0.75), "The rest pose leaves the right side empty")
        XCTAssertTrue(hasContent(frames[1], inColumnsFrom: 0.75), "The swapped-in geometry must render skinned")
    }

    // MARK: - Posed Views

    func testPosedViewWithIdentityPaletteMatchesSource() throws {
        let source = try VisualTestHarness.render(size: [160, 160]) { renderer, camera in
            let mesh = Mesh(context: renderer.context, label: "Bar", geometry: makeBarGeometry(context: renderer.context, withJoints: true),
                            material: NormalColorMaterial(context: renderer.context))
            mesh.cullMode = .none
            return (scene: Object(context: renderer.context, label: "Scene", [mesh]), camera: camera)
        }
        let view = try renderPosedViews(poses: [[matrix_identity_float4x4, matrix_identity_float4x4]], sourceHasJoints: true,
                                        material: { NormalColorMaterial(context: $0) })
        XCTAssertEqual(source.pixels, view.pixels, "A view in the identity pose must render exactly like its source")
    }

    func testTwoPosedViewsPoseOneSourceIndependently() throws {
        let leftOfBar = CGRect(x: 0.08, y: 0.05, width: 0.3, height: 0.9)
        var sharedSource: Geometry?
        var views: [PosedGeometry] = []
        let image = try renderPosedViews(poses: [
            [matrix_identity_float4x4, translation(x: 1.0)],
            [matrix_identity_float4x4, translation(x: -1.0)],
        ], sourceHasJoints: true, inspect: { source, posedViews in
            sharedSource = source
            views = posedViews
        })
        VisualTestHarness.assertContainsVisibleContent(image, in: ImageRegion(name: "right of bar", normalizedRect: rightOfBar), minimumChangedPixelRatio: 0.03)
        VisualTestHarness.assertContainsVisibleContent(image, in: ImageRegion(name: "left of bar", normalizedRect: leftOfBar), minimumChangedPixelRatio: 0.03)
        XCTAssertNil(sharedSource?.jointPalette, "Views must not pose their source")
        for view in views {
            XCTAssertTrue(view.vertexBuffers.isEmpty, "Views draw the source's buffers instead of copying them")
        }
    }

    func testPosedViewOfUnskinnedSourceRendersUnskinned() throws {
        let plain = try renderBar(skinned: false, palette: nil) { BasicColorMaterial(context: $0) }
        let view = try renderPosedViews(poses: [[matrix_identity_float4x4, translation(x: 1.0)]], sourceHasJoints: false)
        XCTAssertEqual(plain.pixels, view.pixels, "A palette without joint attributes to apply to must not change rendering")
    }

    func testSourceChangesReachPosedView() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let source = makeBarGeometry(context: context, withJoints: false)
        let jointPalette = JointPalette(device: device, jointCount: 2)
        let view = PosedGeometry(source: source, jointPalette: jointPalette)
        XCTAssertFalse(view.isSkinned)

        var notifications = 0
        let subscription = view.onUpdate.sink { _ in notifications += 1 }
        let jointedBar = makeBarGeometry(context: context, withJoints: true)
        for index in [VertexAttributeIndex.JointIndices, .JointWeights] {
            source.addAttribute(try XCTUnwrap(jointedBar.getAttribute(index)), for: index)
        }
        withExtendedLifetime(subscription) {
            XCTAssertGreaterThan(notifications, 0, "Meshes drawing the view must hear about changes to its source")
        }
        XCTAssertTrue(view.isSkinned, "Joint attributes added to the source skin the view")
        XCTAssertEqual(view.vertexDescriptor.attributes[VertexAttributeIndex.JointIndices.rawValue].format, .ushort4,
                       "The view's layout follows the source's")
    }

    // MARK: - Helpers

    /// The bar drawn once per pose, each by its own mesh through its own `PosedGeometry` of one
    /// shared source. `inspect` receives the source and the views.
    private func renderPosedViews(poses: [[simd_float4x4]], sourceHasJoints: Bool,
                                  material makeMaterial: (Context) -> Material = { BasicColorMaterial(context: $0) },
                                  inspect: (Geometry, [PosedGeometry]) -> Void = { _, _ in }) throws -> RGBAImage
    {
        try VisualTestHarness.render(size: [160, 160]) { renderer, camera in
            let context = renderer.context
            let source = makeBarGeometry(context: context, withJoints: sourceHasJoints)
            let views = poses.map { pose in
                let jointPalette = JointPalette(device: context.device, jointCount: pose.count)
                jointPalette.reset(matrices: pose)
                return PosedGeometry(source: source, jointPalette: jointPalette)
            }
            inspect(source, views)
            let meshes = views.map { view in
                let mesh = Mesh(context: context, label: "Bar", geometry: view, material: makeMaterial(context))
                mesh.cullMode = .none
                return mesh
            }
            return (scene: Object(context: context, label: "Scene", meshes), camera: camera)
        }
    }

    /// With `lit`, adds a shadow-casting directional light and a floor below the bar that
    /// receives the bar's shadow.
    private func renderBar(skinned: Bool, palette: [simd_float4x4]?, lit: Bool = false, material makeMaterial: (Context) -> Material) throws -> RGBAImage {
        try VisualTestHarness.render(size: [160, 160]) { renderer, camera in
            let context = renderer.context
            let geometry = makeBarGeometry(context: context, withJoints: skinned)
            if let palette {
                let jointPalette = JointPalette(device: context.device, jointCount: palette.count)
                jointPalette.reset(matrices: palette)
                geometry.jointPalette = jointPalette
            }
            let mesh = Mesh(context: context, label: "Bar", geometry: geometry, material: makeMaterial(context))
            mesh.cullMode = .none
            let scene = Object(context: context, label: "Scene", [mesh])

            if lit {
                let light = DirectionalLight(context: context, color: simd_float3(repeating: 1.0), intensity: 1.5)
                light.position = [1.5, 3.0, 2.5]
                light.lookAt(target: .zero, up: Satin.worldUpDirection)
                light.castShadow = true
                light.shadow.resolution = (width: 512, height: 512)
                if let shadowCamera = light.shadow.camera as? OrthographicCamera {
                    shadowCamera.update(left: -3.0, right: 3.0, bottom: -3.0, top: 3.0)
                }
                let floor = Mesh(
                    context: context,
                    label: "Floor",
                    geometry: PlaneGeometry(context: context, size: 6.0, orientation: .zx),
                    material: BasicDiffuseMaterial(context: context, color: simd_float4(0.6, 0.6, 0.65, 1.0), blending: .disabled, hardness: 0.2)
                )
                floor.position.y = -1.05
                floor.receiveShadow = true
                mesh.castShadow = true
                scene.add(light)
                scene.add(floor)
            }
            return (scene: scene, camera: camera)
        }
    }

    /// The bar with joints and a palette holding `pose`, with no motion.
    private func makeSkinnedBar(context: Context, pose: [simd_float4x4]) -> Geometry {
        let geometry = makeBarGeometry(context: context, withJoints: true)
        let jointPalette = JointPalette(device: context.device, jointCount: pose.count)
        jointPalette.reset(matrices: pose)
        geometry.jointPalette = jointPalette
        return geometry
    }

    /// The bar drawn with `VelocityMaterial`. With poses, the palette holds `previousPose` as
    /// last frame's and `currentPose` as this frame's.
    private func renderBarVelocity(previousPose: [simd_float4x4]?, currentPose: [simd_float4x4]?) throws -> [UInt16] {
        let frames = try renderVelocityFrames(frameCount: 1) { context in
            let geometry = makeBarGeometry(context: context, withJoints: previousPose != nil)
            if let previousPose, let currentPose {
                let jointPalette = JointPalette(device: context.device, jointCount: currentPose.count)
                jointPalette.reset(matrices: previousPose)
                jointPalette.update(matrices: currentPose)
                geometry.jointPalette = jointPalette
            }
            let mesh = Mesh(context: context, label: "Bar", geometry: geometry, material: VelocityMaterial(context: context))
            mesh.cullMode = .none
            return Object(context: context, label: "Scene", [mesh])
        } beforeFrame: { _ in }
        return frames[0]
    }

    /// Renders `frameCount` frames of one scene with `VelocityMaterial`-style output into a
    /// two-channel half-float target, the format velocity is written in, and returns each
    /// frame as raw half-float bits (two per pixel). `beforeFrame` runs before each frame.
    private func renderVelocityFrames(frameCount: Int, makeScene: (Context) -> Object, beforeFrame: (Int) -> Void) throws -> [[UInt16]] {
        let size = 160
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .rg16Float, depthPixelFormat: .depth32Float)
        let renderer = RenderEncoder(context: context, clearColor: .zero)
        renderer.resize((width: Float(size), height: Float(size)))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100.0, fov: 30.0)
        camera.aspect = 1
        let scene = makeScene(context)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float, width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))

        var frames: [[UInt16]] = []
        for frame in 0 ..< frameCount {
            beforeFrame(frame)
            let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
            renderer.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, scene: scene, camera: camera, renderTarget: target)
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.synchronize(resource: target)
                blitEncoder.endEncoding()
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            if let error = commandBuffer.error { throw error }

            var values = [UInt16](repeating: 0, count: size * size * 2)
            values.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                target.getBytes(baseAddress, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            }
            frames.append(values)
        }
        return frames
    }

    /// Whether any pixel of a two-channel half-float frame (from `renderVelocityFrames`) is
    /// non-zero at or right of `fraction` of the width.
    private func hasContent(_ values: [UInt16], inColumnsFrom fraction: Double, size: Int = 160) -> Bool {
        let firstColumn = Int(Double(size) * fraction)
        for row in 0 ..< size {
            for column in firstColumn ..< size {
                let index = (row * size + column) * 2
                if values[index] & 0x7FFF != 0 || values[index + 1] & 0x7FFF != 0 { return true }
            }
        }
        return false
    }

    private func translation(x: Float) -> simd_float4x4 {
        matrix_float4x4(columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(x, 0, 0, 1)
        ))
    }

    private func differingPixelRatio(_ first: RGBAImage, _ second: RGBAImage) -> Double {
        guard first.pixels.count == second.pixels.count, !first.pixels.isEmpty else { return 1 }
        var differing = 0
        for pixel in stride(from: 0, to: first.pixels.count, by: 4) where first.pixels[pixel ..< pixel + 4] != second.pixels[pixel ..< pixel + 4] {
            differing += 1
        }
        return Double(differing) / Double(first.pixels.count / 4)
    }

    /// A vertical bar, 0.4 wide and 2 tall, facing the camera, as plain triangles. With joints,
    /// vertices above y = 0 follow joint 1 and the rest follow joint 0, each with weight 1.
    private func makeBarGeometry(context: Context, withJoints: Bool) -> Geometry {
        let rowCount = 8
        let halfWidth: Float = 0.2
        var positions: [simd_float3] = []
        for row in 0 ..< rowCount {
            let bottom = -1 + 2 * Float(row) / Float(rowCount)
            let top = -1 + 2 * Float(row + 1) / Float(rowCount)
            positions += [
                simd_float3(-halfWidth, bottom, 0), simd_float3(halfWidth, bottom, 0), simd_float3(halfWidth, top, 0),
                simd_float3(-halfWidth, bottom, 0), simd_float3(halfWidth, top, 0), simd_float3(-halfWidth, top, 0),
            ]
        }
        let geometry = Geometry(context: context)
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: positions), for: .Position)
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: Array(repeating: simd_float3(0, 0, 1), count: positions.count)), for: .Normal)
        geometry.addAttribute(Float2BufferAttribute(defaultValue: .zero, data: positions.map { simd_float2($0.x + 0.5, $0.y * 0.5 + 0.5) }), for: .Texcoord)
        if withJoints {
            let indices = positions.map { simd_ushort4($0.y > 1e-4 ? 1 : 0, 0, 0, 0) }
            geometry.addAttribute(UShort4BufferAttribute(defaultValue: simd_ushort4(0, 0, 0, 0), data: indices), for: .JointIndices)
            geometry.addAttribute(Float4BufferAttribute(defaultValue: .zero, data: Array(repeating: simd_float4(1, 0, 0, 0), count: positions.count)), for: .JointWeights)
        }
        return geometry
    }
}
