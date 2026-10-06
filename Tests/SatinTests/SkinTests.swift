import Metal
import Satin
import simd
import XCTest

/// `Skin` palette math: palette[j] = inverse(meshWorld) × jointWorld[j] × inverseBind[j].
final class SkinTests: XCTestCase {
    func testBindPoseGivesIdentity() {
        let bindPoses = [translation(0, 1, 0), translation(0, 2, 0) * rotation(.pi / 4, axis: [0, 0, 1])]
        let matrices = Skin.jointMatrices(
            meshWorldMatrix: matrix_identity_float4x4,
            jointWorldMatrices: bindPoses,
            inverseBindMatrices: bindPoses.map(\.inverse)
        )
        for matrix in matrices { assertEqual(matrix, matrix_identity_float4x4) }
    }

    func testSkinFollowsTheMesh() {
        // Moving the mesh and its joints together must not bend anything.
        let bindPose = translation(0, 1, 0)
        let meshWorld = translation(3, -2, 5) * rotation(.pi / 3, axis: [0, 1, 0])
        let matrices = Skin.jointMatrices(
            meshWorldMatrix: meshWorld,
            jointWorldMatrices: [meshWorld * bindPose],
            inverseBindMatrices: [bindPose.inverse]
        )
        assertEqual(matrices[0], matrix_identity_float4x4)
    }

    func testJointRotationMovesBoundVertex() {
        // A joint bound at (0, 1, 0), turned 90° about z at that point: a vertex at (1, 1, 0)
        // swings to (0, 2, 0).
        let bindPose = translation(0, 1, 0)
        let posed = translation(0, 1, 0) * rotation(.pi / 2, axis: [0, 0, 1])
        let matrices = Skin.jointMatrices(
            meshWorldMatrix: matrix_identity_float4x4,
            jointWorldMatrices: [posed],
            inverseBindMatrices: [bindPose.inverse]
        )
        let moved = matrices[0] * simd_float4(1, 1, 0, 1)
        XCTAssertEqual(moved.x, 0, accuracy: 1e-5)
        XCTAssertEqual(moved.y, 2, accuracy: 1e-5)
        XCTAssertEqual(moved.z, 0, accuracy: 1e-5)
    }

    func testSkinTracksObjectHierarchyAndKeepsPreviousPose() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let root = Object(context: context, label: "Root")
        let child = Object(context: context, label: "Child")
        child.position = [0, 1, 0]
        root.add(child)

        let skin = Skin(device: device, joints: [root, child], inverseBindMatrices: [root.worldMatrix.inverse, child.worldMatrix.inverse])
        skin.update(meshWorldMatrix: matrix_identity_float4x4)
        for joint in skin.palette.joints {
            assertEqual(joint.current, matrix_identity_float4x4)
            assertEqual(joint.previous, matrix_identity_float4x4)
        }

        // Moving the root carries the child; both palette entries become that translation.
        root.position = [2, 0, 0]
        skin.update(meshWorldMatrix: matrix_identity_float4x4)
        for joint in skin.palette.joints {
            assertEqual(joint.current, translation(2, 0, 0))
            assertEqual(joint.previous, matrix_identity_float4x4)
        }
    }

    // MARK: - Helpers

    private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        matrix_float4x4(columns: (simd_float4(1, 0, 0, 0), simd_float4(0, 1, 0, 0), simd_float4(0, 0, 1, 0), simd_float4(x, y, z, 1)))
    }

    private func rotation(_ angle: Float, axis: simd_float3) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
    }

    private func assertEqual(_ actual: simd_float4x4, _ expected: simd_float4x4, file: StaticString = #filePath, line: UInt = #line) {
        for column in 0 ..< 4 {
            for row in 0 ..< 4 {
                XCTAssertEqual(actual[column][row], expected[column][row], accuracy: 1e-5, file: file, line: line)
            }
        }
    }
}
