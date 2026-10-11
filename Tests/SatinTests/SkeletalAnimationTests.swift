import Metal
@testable import Satin
import simd
import XCTest

/// Animation through `loadAnimatedAsset`: keyed transforms, skeletons posed by animation or by
/// code, joint influences in the layout Satin skins with, palettes that pose loaded meshes as
/// UsdSkel defines, and animated objects.
final class SkeletalAnimationTests: XCTestCase {
    // MARK: - Transform Animation

    func testKeysHoldOutsideTheRangeAndInterpolateInside() throws {
        let channel = TransformAnimation.Channel<simd_float3>(keyTimes: [1, 2, 4], values: [.zero, .zero, .zero], targetCount: 1)
        XCTAssertEqual(channel.surroundingKeys(at: 0), TransformAnimation.Keys(lower: 0, upper: 0, fraction: 0))
        XCTAssertEqual(channel.surroundingKeys(at: 9), TransformAnimation.Keys(lower: 2, upper: 2, fraction: 0))
        XCTAssertEqual(channel.surroundingKeys(at: 3), TransformAnimation.Keys(lower: 1, upper: 2, fraction: 0.5))
        XCTAssertNil(TransformAnimation.Channel<simd_float3>.empty.surroundingKeys(at: 0))
    }

    func testChannelsDropKeysWithoutAFullSetOfValues() {
        let channel = TransformAnimation.Channel<simd_float3>(keyTimes: [0, 1, 2], values: [.zero, .zero, .one], targetCount: 2)
        XCTAssertEqual(channel.keyTimes, [0], "Key 1 has one value for two targets")
        XCTAssertEqual(channel.values.count, 2)
    }

    func testTransformsInterpolateAndKeepUnkeyedComponents() {
        let quarterTurn = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        let animation = TransformAnimation(
            paths: ["Target"],
            translations: .init(keyTimes: [0, 1], values: [[0, 0, 0], [2, 4, 6]], targetCount: 1),
            rotations: .init(keyTimes: [0, 1], values: [simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), quarterTurn], targetCount: 1),
            scales: .empty
        )
        XCTAssertEqual(animation.timeRange, 0 ... 1)
        let fallback = TransformComponents(scale: [3, 3, 3])
        let transform = animation.transform(of: 0, in: animation.sample(at: 0.5), fallback: fallback)
        let expected = TransformComponents(translation: [1, 2, 3], rotation: simd_quatf(angle: .pi / 4, axis: [0, 0, 1]), scale: [3, 3, 3]).matrix
        assertEqual(transform, expected)
    }

    func testComponentsRoundTripAMatrix() {
        let components = TransformComponents(translation: [1, -2, 3], rotation: simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3])), scale: [2, 0.5, 1.5])
        assertEqual(TransformComponents(matrix: components.matrix).matrix, components.matrix)
    }

    func testComponentsKeepAMirroredMatrixMirrored() {
        let mirrored = TransformComponents(translation: [1, 2, 3], rotation: simd_quatf(angle: 0.4, axis: [0, 1, 0]), scale: [1, -2, 1]).matrix
        XCTAssertLessThan(simd_determinant(mirrored), 0)
        let roundTrip = TransformComponents(matrix: mirrored).matrix
        XCTAssertLessThan(simd_determinant(roundTrip), 0, "Handedness survives")
        assertEqual(roundTrip, mirrored)
    }

    // MARK: - Joint Influences

    func testStrongestFourInfluencesAreKeptAndRenormalized() {
        let influences = strongestJointInfluences(indices: [0, 1, 2, 3, 4, 5], weights: [0.05, 0.3, 0.1, 0.25, 0.2, 0.1], jointCount: 6)
        // Joints 2 and 5 tie at 0.1; the earlier one wins.
        XCTAssertEqual(influences.indices, simd_ushort4(1, 3, 4, 2))
        assertEqual(influences.weights, simd_float4(0.3, 0.25, 0.2, 0.1) / 0.85)
    }

    func testAVertexWithoutWeightGoesToTheRestJoint() {
        let influences = strongestJointInfluences(indices: [3, 7], weights: [0, 0], jointCount: 10)
        XCTAssertEqual(influences.indices, simd_ushort4(10, 0, 0, 0))
        XCTAssertEqual(influences.weights, simd_float4(1, 0, 0, 0))
    }

    func testInfluencesOutsideTheJointsAreDropped() {
        // The GPU would read past the palette for joint 12.
        let influences = strongestJointInfluences(indices: [2, 12], weights: [0.5, 0.5], jointCount: 10)
        XCTAssertEqual(influences.indices, simd_ushort4(2, 0, 0, 0))
        XCTAssertEqual(influences.weights, simd_float4(1, 0, 0, 0))
    }

    // MARK: - Skeleton

    func testBindPoseGivesIdentity() {
        let bindPoses = [translation(0, 1, 0), translation(0, 2, 0) * rotation(.pi / 4, axis: [0, 0, 1])]
        var matrices: [simd_float4x4] = []
        SkeletonBinding.computeJointMatrices(&matrices, jointTransforms: bindPoses, skeletonJointIndices: [0, 1],
                                             inverseBindMatrices: bindPoses.map(\.inverse), geometryBindTransform: matrix_identity_float4x4,
                                             skeletonToGeometry: matrix_identity_float4x4)
        XCTAssertEqual(matrices.count, 3, "Two joints, then the rest joint")
        for matrix in matrices { assertEqual(matrix, matrix_identity_float4x4) }
    }

    func testJointRotationMovesBoundVertex() throws {
        // A joint bound at (0, 1, 0), turned 90° about z at that point: a vertex at (1, 1, 0)
        // swings to (0, 2, 0).
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let skeleton = Skeleton(jointPaths: ["Joint"], restTransforms: [translation(0, 1, 0)], bindTransforms: [translation(0, 1, 0)])
        let binding = skeleton.bind(device: device, mesh: nil, jointPaths: nil, geometryBindTransform: matrix_identity_float4x4)
        skeleton.setLocalTransforms([translation(0, 1, 0) * rotation(.pi / 2, axis: [0, 0, 1])])
        skeleton.commitPose()
        let moved = binding.palette.joints[0].current * simd_float4(1, 1, 0, 1)
        assertEqual(simd_make_float3(moved), [0, 2, 0])
    }

    func testSkeletonComposesParentsAndMatchesAnimatedJointsByPath() {
        // The animation drives only Elbow, listed alone; Root keeps its rest transform.
        let animation = TransformAnimation(
            paths: ["Root/Elbow"],
            translations: .init(keyTimes: [0], values: [[0, 1, 0]], targetCount: 1),
            rotations: .init(keyTimes: [0], values: [simd_quatf(angle: .pi / 2, axis: [0, 0, 1])], targetCount: 1),
            scales: .empty
        )
        let skeleton = Skeleton(jointPaths: ["Root", "Root/Elbow"], restTransforms: [translation(3, 0, 0), translation(0, 1, 0)],
                                bindTransforms: [], animation: animation)
        XCTAssertEqual(skeleton.parentIndices, [-1, 0])
        skeleton.setTime(0)
        assertEqual(skeleton.jointTransforms[0], translation(3, 0, 0))
        assertEqual(skeleton.jointTransforms[1], translation(3, 1, 0) * rotation(.pi / 2, axis: [0, 0, 1]))
    }

    func testCodeAndAnimationCommitTogetherAndKeepThePreviousPose() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let animation = TransformAnimation(
            paths: ["Root/Elbow"],
            translations: .init(keyTimes: [0, 1], values: [[0, 1, 0], [0, 2, 0]], targetCount: 1),
            rotations: .empty,
            scales: .empty
        )
        let skeleton = Skeleton(jointPaths: ["Root", "Root/Elbow"], restTransforms: [matrix_identity_float4x4, translation(0, 1, 0)],
                                bindTransforms: [matrix_identity_float4x4, translation(0, 1, 0)], animation: animation)
        let binding = skeleton.bind(device: device, mesh: nil, jointPaths: nil, geometryBindTransform: matrix_identity_float4x4)

        // One frame: code moves Root, which the animation does not drive, the animation moves
        // Elbow, and one commit uploads both.
        skeleton.setLocalTransforms([translation(5, 0, 0)])
        skeleton.applyAnimation(at: 1)
        skeleton.commitPose()
        assertEqual(skeleton.jointTransforms[1], translation(5, 2, 0), "Elbow rides Root's coded move")
        assertEqual(binding.palette.joints[0].current, translation(5, 0, 0))
        assertEqual(binding.palette.joints[0].previous, matrix_identity_float4x4, "Last frame's Root is the rest pose, not a half-applied one")
        assertEqual(binding.palette.joints[1].current, translation(5, 1, 0))
        assertEqual(binding.palette.joints[1].previous, matrix_identity_float4x4)
        assertEqual(binding.palette.joints[2].current, matrix_identity_float4x4, "The rest joint stays identity")
    }

    func testSkinFollowsTheSkeletonAnchorNotTheMesh() throws {
        let context = try makeContext()
        let anchor = Object(context: context, label: "Anchor")
        let mesh = Object(context: context, label: "Mesh")
        let skeleton = Skeleton(jointPaths: ["Joint"], restTransforms: [], bindTransforms: [], anchor: anchor)
        let binding = skeleton.bind(device: context.device, mesh: mesh, jointPaths: nil, geometryBindTransform: matrix_identity_float4x4)
        func drawn() -> simd_float3 {
            simd_make_float3(mesh.worldMatrix * binding.palette.joints[0].current * simd_float4(0.5, 0, 0, 1))
        }

        anchor.position = [10, 0, 0]
        skeleton.commitPose()
        assertEqual(drawn(), simd_float3(10.5, 0, 0))

        mesh.position = [0, 5, 0]
        skeleton.commitPose()
        assertEqual(drawn(), simd_float3(10.5, 0, 0), "The mesh's own move does not carry skinned geometry")
    }

    func testUnweightedAndUnnamedJointsStayWithTheBoundSkin() throws {
        // At rest, a weighted vertex lands at skeletonWorld × geometryBind × p; vertices on a
        // joint the skeleton does not name, or on the rest joint, must land there too.
        let context = try makeContext()
        let anchor = Object(context: context, label: "Anchor")
        let skeleton = Skeleton(jointPaths: ["Joint"], restTransforms: [], bindTransforms: [], anchor: anchor)
        let binding = skeleton.bind(device: context.device, mesh: nil, jointPaths: ["Joint", "Missing"],
                                    geometryBindTransform: translation(0, 3, 0))
        anchor.position = [10, 0, 0]
        skeleton.commitPose()

        let point = simd_float4(1, 0, 0, 1)
        assertEqual(simd_make_float3(binding.palette.joints[0].current * point), simd_float3(11, 3, 0))
        assertEqual(simd_make_float3(binding.palette.joints[1].current * point), simd_float3(11, 3, 0), "Unnamed joint")
        assertEqual(simd_make_float3(binding.palette.joints[binding.restJointIndex].current * point), simd_float3(11, 3, 0), "Rest joint")
    }

    // MARK: - Loading

    /// moving_skeleton.usda: Rig, holding the skeleton, slides 10 along x; Holder, holding the
    /// mesh, slides 5 along y. The vertex follows Rig only.
    func testLoadedSkinFollowsItsSkeletonsAnimatedPlacement() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "moving_skeleton", withExtension: "usda"))
        let loaded = loadAnimatedAsset(url: url, context: try makeContext())
        let animation = try XCTUnwrap(loaded.animation)
        XCTAssertEqual(animation.objectAnimation?.objects.map(\.label).sorted(), ["Holder", "Rig"])
        let mesh = try XCTUnwrap(loaded.root.getChildren().compactMap { $0 as? Mesh }.first)

        animation.setTime(0)
        assertPosed(mesh, [[0.5, 0, 0]: [0.5, 0, 0]])
        animation.setTime(1)
        assertPosed(mesh, [[0.5, 0, 0]: [10.5, 0, 0]])
    }

    func testStaticLoadingReadsOnlyTheStartPose() throws {
        let context = try makeContext()
        let mover = try XCTUnwrap(Bundle.module.url(forResource: "animated_mover", withExtension: "usda"))
        let objectAnimation = try XCTUnwrap(loadAssetHierarchy(url: mover, context: context, textureLoader: nil, startPoseOnly: true).animation?.objectAnimation)
        XCTAssertEqual(objectAnimation.animation.translations.keyTimes, [0])

        let bar = try XCTUnwrap(Bundle.module.url(forResource: "two_joint_bar", withExtension: "usda"))
        let skeleton = try XCTUnwrap(loadAssetHierarchy(url: bar, context: context, textureLoader: nil, startPoseOnly: true).animation?.skeletons.first)
        XCTAssertEqual(skeleton.animation?.rotations.keyTimes, [0])
    }

    /// two_joint_bar.usda: Elbow sits 1 above Root and turns 90° about z from t = 0 to t = 1.
    /// Root's vertex stays put, Elbow's swings about (0, 1, 0), the half-and-half vertex lands
    /// between them, and the unweighted vertex stays at rest.
    func testLoadedBarPosesAsUsdSkelDefines() throws {
        let (animation, mesh) = try loadBar()
        let skeleton = try XCTUnwrap(animation.skeletons.first)
        XCTAssertEqual(skeleton.jointPaths, ["Root", "Root/Elbow"])
        XCTAssertEqual(skeleton.bindings.count, 1)
        XCTAssertEqual(skeleton.bindings[0].skeletonJointIndices, [1, 0], "The mesh lists Elbow, then Root")
        XCTAssertEqual(skeleton.bindings[0].palette.jointCount, 3, "Two joints, then the rest joint")
        XCTAssertTrue(mesh.geometry.isSkinned)

        animation.setTime(0)
        assertPosed(mesh, [[0.5, 0, 0]: [0.5, 0, 0], [0.5, 2, 0]: [0.5, 2, 0], [0.5, 1, 0]: [0.5, 1, 0]])

        animation.setTime(0.5)
        let eighth = Float.pi / 4
        assertPosed(mesh, [
            [0.5, 0, 0]: [0.5, 0, 0],
            [0.5, 2, 0]: [0.5 * cos(eighth) - sin(eighth), 1 + 0.5 * sin(eighth) + cos(eighth), 0],
        ])

        animation.setTime(1)
        assertPosed(mesh, [[0.5, 0, 0]: [0.5, 0, 0], [0.5, 2, 0]: [-1, 1.5, 0], [0.5, 1, 0]: [0.25, 1.25, 0], [3, 2, 0]: [3, 2, 0]])
    }

    func testAnAnimationBoundByTheMeshPosesIt() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "animation_on_mesh", withExtension: "usda"))
        let loaded = loadAnimatedAsset(url: url, context: try makeContext())
        let animation = try XCTUnwrap(loaded.animation)
        XCTAssertNotNil(animation.skeletons.first?.animation, "The mesh's binding names the animation")
        let mesh = try XCTUnwrap(loaded.root.getChildren().compactMap { $0 as? Mesh }.first)
        animation.setTime(1)
        assertPosed(mesh, [[0.5, 2, 0]: [-1, 1.5, 0]])
    }

    func testLoadingStartsStillAndTimeChangesKeepTheOutgoingPose() throws {
        let (animation, mesh) = try loadBar()
        let palette = try XCTUnwrap(mesh.geometry.jointPalette)
        for joint in palette.joints { assertEqual(joint.previous, joint.current, "Loaded without motion") }
        let startPose = palette.joints.map(\.current)
        animation.setTime(1)
        for (joint, start) in zip(palette.joints, startPose) {
            assertEqual(joint.previous, start)
        }
    }

    func testPosedBoundsFollowTheLoadedAnimation() throws {
        let (animation, mesh) = try loadBar()
        animation.setTime(0)
        mesh.update()
        XCTAssertEqual(mesh.localBounds.min.x, 0.5, accuracy: 1e-4)
        XCTAssertEqual(mesh.localBounds.max.x, 3, accuracy: 1e-4, "The unweighted vertex rests at x = 3")
        animation.setTime(1)
        mesh.update()
        // Elbow's box spans its vertices from y 1 to 2 at x 0.5; turned a quarter about
        // (0, 1, 0) it spans x -1 to 0, so the bounds reach x = -1 and still hold the
        // unweighted vertex where it rests.
        XCTAssertEqual(mesh.localBounds.min.x, -1, accuracy: 1e-4, "Elbow's vertex swings to x = -1")
        XCTAssertEqual(mesh.localBounds.max.x, 3, accuracy: 1e-4)
    }

    /// animated_mover.usda: Mover slides 2 along x and turns 90° about z over one second; its
    /// child Box sits 1 above it, so Box's vertex at (1, 0, 0) is at (1, 1, 0) at both ends and
    /// at (1, √2, 0) halfway.
    func testAnimatedObjectsMoveTheirChildren() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "animated_mover", withExtension: "usda"))
        let loaded = loadAnimatedAsset(url: url, context: try makeContext())
        let animation = try XCTUnwrap(loaded.animation)
        XCTAssertEqual(animation.timeRange, 0 ... 1)
        XCTAssertTrue(animation.skeletons.isEmpty)
        let objectAnimation = try XCTUnwrap(animation.objectAnimation)
        XCTAssertEqual(objectAnimation.objects.map(\.label), ["Mover"], "Only Mover's transform is animated")
        let box = try XCTUnwrap(loaded.root.getChildren().compactMap { $0 as? Mesh }.first)

        for (time, expected) in [(0.0, simd_float3(1, 1, 0)), (0.5, simd_float3(1, sqrt(2), 0)), (1.0, simd_float3(1, 1, 0))] {
            animation.setTime(time)
            assertEqual(simd_make_float3(box.worldMatrix * simd_float4(1, 0, 0, 1)), expected)
        }
    }

    func testFlattenedLoadKeepsTheStartPose() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "animated_mover", withExtension: "usda"))
        let model = try XCTUnwrap(loadAsset(url: url, context: try makeContext()))
        let box = try XCTUnwrap(model.children.first as? Mesh, "Meshes sit directly under the root")
        assertEqual(simd_make_float3(box.worldMatrix * simd_float4(1, 0, 0, 1)), [1, 1, 0])
    }

    /// Apple's chameleon (Example assets): 84 joints, five skinned meshes with their own joint
    /// subsets and up to 12 influences per vertex.
    func testChameleonLoadsEverySkinnedMesh() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Example/Assets/Shared/Models/chameleon_anim_mtl_variant.usdz")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "The chameleon example asset is not present")
        let loaded = loadAnimatedAsset(url: url, context: try makeContext())
        let animation = try XCTUnwrap(loaded.animation)

        XCTAssertEqual(animation.skeletons.count, 1)
        let skeleton = try XCTUnwrap(animation.skeletons.first)
        XCTAssertEqual(skeleton.jointPaths.count, 84)
        XCTAssertEqual(skeleton.bindings.map(\.skeletonJointIndices.count).sorted(), [1, 1, 10, 60, 60])
        let timeRange = try XCTUnwrap(animation.timeRange)
        XCTAssertEqual(timeRange.upperBound, 607.0 / 30.0, accuracy: 1e-6)
        XCTAssertNil(animation.objectAnimation, "The stick has one transform sample: it does not move")

        let skinnedMeshes = loaded.root.getChildren().compactMap { $0 as? Mesh }.filter(\.geometry.isSkinned)
        XCTAssertEqual(skinnedMeshes.count, 5)
        for mesh in skinnedMeshes {
            let weights = try XCTUnwrap(mesh.geometry.getAttribute(.JointWeights) as? Float4BufferAttribute)
            let jointIndices = try XCTUnwrap(mesh.geometry.getAttribute(.JointIndices) as? UShort4BufferAttribute)
            let jointCount = try XCTUnwrap(mesh.geometry.jointPalette).jointCount
            for (indices, vertexWeights) in zip(jointIndices.data, weights.data) {
                XCTAssertEqual(vertexWeights.sum(), 1, accuracy: 1e-4)
                for influence in 0 ..< 4 where vertexWeights[influence] > 0 {
                    XCTAssertLessThan(Int(indices[influence]), jointCount)
                }
            }
        }

        // Loaded at the animation's first frame, which is not the rest pose, without motion.
        XCTAssertTrue(zip(skeleton.localTransforms, skeleton.restTransforms).contains { !isClose($0, $1) }, "Posed at the start, not at rest")
        for binding in skeleton.bindings {
            XCTAssertTrue(binding.palette.joints.allSatisfy { isClose($0.previous, $0.current) }, "Loaded without motion")
        }

        // The idle animation moves joints between its start and middle.
        let startPose = skeleton.jointTransforms
        animation.setTime((timeRange.lowerBound + timeRange.upperBound) / 2)
        XCTAssertTrue(zip(startPose, skeleton.jointTransforms).contains { !isClose($0, $1) })

        // Bounds from joint boxes hold every vertex where the pose puts it.
        for mesh in skinnedMeshes {
            let exact = try XCTUnwrap(mesh.geometry.currentPosedBVH()?.getNode(index: 0)?.aabb)
            let bounds = mesh.geometry.bounds
            XCTAssertTrue(all(bounds.min .<= exact.min + 1e-4) && all(bounds.max .>= exact.max - 1e-4),
                          "\(mesh.label): \(bounds) does not hold \(exact)")
        }
    }

    // MARK: - Helpers

    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func loadBar() throws -> (AssetAnimation, Mesh) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "two_joint_bar", withExtension: "usda"))
        let loaded = loadAnimatedAsset(url: url, context: try makeContext())
        let animation = try XCTUnwrap(loaded.animation)
        let mesh = try XCTUnwrap(loaded.root.getChildren().compactMap { $0 as? Mesh }.first)
        return (animation, mesh)
    }

    /// Checks posed positions in world space, finding each vertex by its rest position.
    private func assertPosed(_ mesh: Mesh, _ expected: [simd_float3: simd_float3], file: StaticString = #filePath, line: UInt = #line) {
        guard let positions = mesh.geometry.getAttribute(.Position) as? PackedFloat3BufferAttribute,
              let jointIndices = mesh.geometry.getAttribute(.JointIndices) as? UShort4BufferAttribute,
              let jointWeights = mesh.geometry.getAttribute(.JointWeights) as? Float4BufferAttribute,
              let palette = mesh.geometry.jointPalette
        else { return XCTFail("The loaded mesh is not skinned", file: file, line: line) }

        for (rest, posed) in expected {
            guard let vertex = positions.data.firstIndex(where: { simd_distance(simd_float3($0.x, $0.y, $0.z), rest) < 1e-5 }) else {
                XCTFail("No vertex rests at \(rest)", file: file, line: line)
                continue
            }
            var skinned = simd_float4.zero
            for influence in 0 ..< 4 {
                let joint = palette.joints[Int(jointIndices.data[vertex][influence])].current
                skinned += jointWeights.data[vertex][influence] * (joint * simd_float4(rest, 1))
            }
            assertEqual(simd_make_float3(mesh.worldMatrix * skinned), posed, file: file, line: line)
        }
    }

    private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        matrix_float4x4(columns: (simd_float4(1, 0, 0, 0), simd_float4(0, 1, 0, 0), simd_float4(0, 0, 1, 0), simd_float4(x, y, z, 1)))
    }

    private func rotation(_ angle: Float, axis: simd_float3) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
    }

    private func isClose(_ first: simd_float4x4, _ second: simd_float4x4) -> Bool {
        (0 ..< 4).allSatisfy { simd_distance(first[$0], second[$0]) < 1e-4 }
    }

    private func assertEqual(_ actual: simd_float4x4, _ expected: simd_float4x4, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(isClose(actual, expected), "\(actual) is not \(expected). \(message)", file: file, line: line)
    }

    private func assertEqual(_ actual: simd_float3, _ expected: simd_float3, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(actual, expected), 1e-4, "\(actual) is not \(expected). \(message)", file: file, line: line)
    }

    private func assertEqual(_ actual: simd_float4, _ expected: simd_float4, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(actual, expected), 1e-5, "\(actual) is not \(expected)", file: file, line: line)
    }
}
