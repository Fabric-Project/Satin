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
/// the space of the mesh drawing it (UsdSkel's skinning, then the skeleton's place relative to
/// the mesh):
///
///     palette[j] = inverse(meshWorld) × skeletonWorld × jointTransform[s(j)] × inverse(bind[s(j)]) × geometryBind
///
/// where `s(j)` is the skeleton joint the geometry's joint `j` names. One more entry follows
/// the geometry's joints, at `restJointIndex`: identity, for vertices no joint moves.
///
/// UsdSkel ignores a skinned mesh's own transform: skinned points land in skeleton space, so
/// they follow the skeleton's anchor, not the mesh. `inverse(meshWorld)` cancels the mesh's
/// model matrix, which Satin applies after the palette; both world matrices are read at each
/// commit, so moving either is reflected then.
public final class SkeletonBinding {
    /// For each of the geometry's joints, the skeleton joint it names; -1 when the skeleton has
    /// no such joint, which leaves its vertices at rest.
    public let skeletonJointIndices: [Int]
    /// For each of the geometry's joints: inverse(bind) × geometryBind.
    public let inverseBindMatrices: [simd_float4x4]
    /// The mesh drawing the geometry; nil places the geometry's space at the world origin.
    public private(set) weak var mesh: Object?
    public let palette: JointPalette

    /// The palette entry that leaves a vertex at rest: the one after the geometry's joints.
    public var restJointIndex: Int { skeletonJointIndices.count }

    private var hasPosed = false
    /// The palette's matrices, kept between poses so posing allocates nothing.
    private var matrices: [simd_float4x4] = []

    init(device: MTLDevice, mesh: Object?, skeletonJointIndices: [Int], inverseBindMatrices: [simd_float4x4]) {
        self.skeletonJointIndices = skeletonJointIndices
        self.inverseBindMatrices = inverseBindMatrices
        self.mesh = mesh
        // The palette fills entries past the given matrices with identity: the rest joint.
        palette = JointPalette(device: device, jointCount: skeletonJointIndices.count + 1)
    }

    /// Recomputes the palette from the skeleton's joint transforms and where the skeleton sits
    /// in the world. The first call sets a pose with no motion; later calls keep the outgoing
    /// pose as last frame's, for velocity.
    func pose(jointTransforms: [simd_float4x4], skeletonWorld: simd_float4x4) {
        let meshWorld = mesh?.worldMatrix ?? matrix_identity_float4x4
        Self.computeJointMatrices(
            &matrices,
            jointTransforms: jointTransforms,
            skeletonJointIndices: skeletonJointIndices,
            inverseBindMatrices: inverseBindMatrices,
            skeletonToGeometry: meshWorld.inverse * skeletonWorld
        )
        if hasPosed {
            palette.update(matrices: matrices)
        } else {
            palette.reset(matrices: matrices)
            hasPosed = true
        }
    }

    /// Writes the palette for a pose into `matrices`, one per geometry joint, reusing its storage.
    public static func computeJointMatrices(
        _ matrices: inout [simd_float4x4],
        jointTransforms: [simd_float4x4],
        skeletonJointIndices: [Int],
        inverseBindMatrices: [simd_float4x4],
        skeletonToGeometry: simd_float4x4
    ) {
        let count = min(skeletonJointIndices.count, inverseBindMatrices.count)
        if matrices.count != count {
            matrices = Array(repeating: matrix_identity_float4x4, count: count)
        }
        for jointIndex in 0 ..< count {
            let skeletonJointIndex = skeletonJointIndices[jointIndex]
            matrices[jointIndex] = jointTransforms.indices.contains(skeletonJointIndex)
                ? skeletonToGeometry * jointTransforms[skeletonJointIndex] * inverseBindMatrices[jointIndex]
                : matrix_identity_float4x4
        }
    }
}
