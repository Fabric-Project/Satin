//
//  Skin.swift
//  Satin
//

import Metal
import simd

/// Poses a skinned geometry from a joint hierarchy, as glTF skins do: each joint is an
/// `Object` in the scene, and moving joints bends the geometry.
///
/// Each palette entry takes a vertex from the geometry's bind pose to its posed position in
/// the skinned mesh's own space (GLTFKit, GLTFMTLRenderer.m):
///
///     palette[j] = inverse(meshWorld) × jointWorld[j] × inverseBind[j]
///
/// `inverseBind[j]` undoes joint j's bind-pose transform, `jointWorld[j]` applies its
/// current one, and `inverse(meshWorld)` returns to mesh space, because the mesh's own
/// model matrix is applied afterwards like any other mesh's.
public final class Skin {
    public let joints: [Object]
    public let inverseBindMatrices: [simd_float4x4]
    public let palette: JointPalette

    private var hasPosed = false

    /// `inverseBindMatrices` holds one matrix per joint, in the same order; missing entries
    /// are identity.
    public init(device: MTLDevice, joints: [Object], inverseBindMatrices: [simd_float4x4]) {
        self.joints = joints
        self.inverseBindMatrices = inverseBindMatrices
        palette = JointPalette(device: device, jointCount: joints.count)
    }

    /// Recomputes the palette from the joints' current world matrices. The first call sets a
    /// pose with no motion; later calls keep the outgoing pose as last frame's, for velocity.
    /// Call once per frame, after joints move, with the skinned mesh's world matrix.
    public func update(meshWorldMatrix: simd_float4x4) {
        let matrices = Self.jointMatrices(
            meshWorldMatrix: meshWorldMatrix,
            jointWorldMatrices: joints.map(\.worldMatrix),
            inverseBindMatrices: inverseBindMatrices
        )
        if hasPosed {
            palette.update(matrices: matrices)
        } else {
            palette.reset(matrices: matrices)
            hasPosed = true
        }
    }

    /// The palette for a pose, without any GPU state.
    public static func jointMatrices(
        meshWorldMatrix: simd_float4x4,
        jointWorldMatrices: [simd_float4x4],
        inverseBindMatrices: [simd_float4x4]
    ) -> [simd_float4x4] {
        let meshWorldInverse = meshWorldMatrix.inverse
        return jointWorldMatrices.enumerated().map { jointIndex, jointWorldMatrix in
            let inverseBindMatrix = jointIndex < inverseBindMatrices.count ? inverseBindMatrices[jointIndex] : matrix_identity_float4x4
            return meshWorldInverse * jointWorldMatrix * inverseBindMatrix
        }
    }
}
