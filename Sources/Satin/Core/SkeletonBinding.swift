//
//  SkeletonBinding.swift
//  Satin
//

import Metal
import simd

/// One skinned geometry's binding to a `Skeleton`, as a USD skinned mesh binds: its own joint
/// order, bind transforms and palette. Made by `Skeleton.bind`, posed whenever the skeleton
/// commits a pose.
///
/// Each palette entry takes a vertex from the geometry's rest pose to its posed position in
/// skeleton space, as UsdSkel skins:
///
///     palette[j] = jointTransform[s(j)] × inverse(bind[s(j)]) × geometryBind
///
/// where `s(j)` is the skeleton joint the geometry's joint `j` names. A joint the skeleton does
/// not name, and one more entry after the geometry's joints at `restJointIndex`, for vertices
/// no joint moves, keep the geometry where it was bound:
///
///     palette[j] = geometryBind
///
/// UsdSkel ignores a skinned mesh's own transform: skinned points land in skeleton space. So a
/// mesh drawing the geometry belongs where the skeleton sits, its model matrix the skeleton's
/// placement; the loader puts each skinned mesh there. The palette holds no placement, so any
/// number of meshes and instances can draw it, and moving the skeleton moves them at once.
public final class SkeletonBinding {
    /// For each of the geometry's joints, the skeleton joint it names; -1 when the skeleton has
    /// no such joint, which leaves its vertices where they were bound.
    public let skeletonJointIndices: [Int]
    /// For each of the geometry's joints: inverse(bind) × geometryBind, or geometryBind for a
    /// joint the skeleton does not name.
    public let inverseBindMatrices: [simd_float4x4]
    /// Places the geometry's rest points in skeleton space at bind time.
    public let geometryBindTransform: simd_float4x4
    public let palette: JointPalette

    /// The palette entry that leaves a vertex at rest: the one after the geometry's joints.
    public var restJointIndex: Int { skeletonJointIndices.count }

    private var hasPosed = false
    /// The palette's matrices, kept between poses so posing allocates nothing.
    private var matrices: [simd_float4x4] = []

    init(device: MTLDevice, skeletonJointIndices: [Int], inverseBindMatrices: [simd_float4x4], geometryBindTransform: simd_float4x4) {
        self.skeletonJointIndices = skeletonJointIndices
        self.inverseBindMatrices = inverseBindMatrices
        self.geometryBindTransform = geometryBindTransform
        palette = JointPalette(jointCount: skeletonJointIndices.count + 1)
    }

    /// Recomputes the palette from the skeleton's joint transforms. The first call sets a pose
    /// with no motion; later poses move against the palette's previous frame when drawn.
    func pose(jointTransforms: [simd_float4x4]) {
        Self.computeJointMatrices(
            &matrices,
            jointTransforms: jointTransforms,
            skeletonJointIndices: skeletonJointIndices,
            inverseBindMatrices: inverseBindMatrices,
            geometryBindTransform: geometryBindTransform
        )
        if hasPosed {
            palette.update(matrices: matrices)
        } else {
            palette.reset(matrices: matrices)
            hasPosed = true
        }
    }

    /// Writes the palette for a pose into `matrices`, one per geometry joint then the rest
    /// joint, reusing its storage.
    public static func computeJointMatrices(
        _ matrices: inout [simd_float4x4],
        jointTransforms: [simd_float4x4],
        skeletonJointIndices: [Int],
        inverseBindMatrices: [simd_float4x4],
        geometryBindTransform: simd_float4x4
    ) {
        let count = min(skeletonJointIndices.count, inverseBindMatrices.count)
        if matrices.count != count + 1 {
            matrices = Array(repeating: matrix_identity_float4x4, count: count + 1)
        }
        for jointIndex in 0 ..< count {
            let skeletonJointIndex = skeletonJointIndices[jointIndex]
            // An unnamed joint's inverse bind matrix is the geometry bind transform alone.
            matrices[jointIndex] = jointTransforms.indices.contains(skeletonJointIndex)
                ? jointTransforms[skeletonJointIndex] * inverseBindMatrices[jointIndex]
                : inverseBindMatrices[jointIndex]
        }
        matrices[count] = geometryBindTransform
    }
}
