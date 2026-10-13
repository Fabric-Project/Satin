//
//  Skeleton.swift
//  Satin
//

import Metal
import simd

/// A joint hierarchy held as data, as a USD `Skeleton` holds it, posed by its animation, by
/// code, or both, and the skinned geometries bound to it.
///
/// Joints are named by path ("Root/Hips/Spine"); a joint's parent is the path without its last
/// component. Parents come before children, as UsdSkel requires; a joint whose parent is
/// missing or listed after it is treated as a root.
///
/// Posing is staged, then committed once per frame:
/// - `applyAnimation(at:)` stages the joints the animation drives; the others keep theirs.
/// - `setLocalTransforms(_:)` stages any joints directly, for procedural motion.
/// - `commitPose()` composes the staged pose and updates every binding's palette once, making
///   the outgoing pose last frame's, for velocity.
/// `setTime(_:)` applies the animation and commits, for skeletons nothing else poses. Stage
/// procedural joints before it, or call the three steps yourself, but commit once a frame.
public final class Skeleton: TimeDriven {
    public let jointPaths: [String]
    /// Each joint's parent index; -1 for roots.
    public let parentIndices: [Int]
    /// Each joint's transform relative to its parent before anything poses it.
    public let restTransforms: [simd_float4x4]
    /// Each joint's transform in skeleton space at the time geometry was bound to it.
    public let bindTransforms: [simd_float4x4]
    public let animation: TransformAnimation?
    public private(set) var bindings: [SkeletonBinding] = []
    /// Where skeleton space sits in the scene: skinned geometry follows it, whatever its own
    /// mesh's transform, as UsdSkel defines. Nil: skeleton space is world space.
    public weak var anchor: Object?

    /// The staged pose: each joint's transform relative to its parent.
    public private(set) var localTransforms: [simd_float4x4]
    /// The committed pose in skeleton space: each joint's local transform composed with its parents'.
    public private(set) var jointTransforms: [simd_float4x4]

    /// For each joint, its index among the animation's targets; nil when the animation does not drive it.
    private let animationTargetIndices: [Int?]
    /// Each joint's rest transform decomposed, for channels the animation does not key.
    private let restDecompositions: [simd_float4x4.Decomposition]

    /// `restTransforms` and `bindTransforms` hold one matrix per joint, in `jointPaths` order;
    /// missing entries are identity. The skeleton starts at rest.
    public init(jointPaths: [String], restTransforms: [simd_float4x4], bindTransforms: [simd_float4x4],
                animation: TransformAnimation? = nil, anchor: Object? = nil) {
        self.anchor = anchor
        self.jointPaths = jointPaths
        self.restTransforms = jointPaths.indices.map { $0 < restTransforms.count ? restTransforms[$0] : matrix_identity_float4x4 }
        self.bindTransforms = jointPaths.indices.map { $0 < bindTransforms.count ? bindTransforms[$0] : matrix_identity_float4x4 }
        self.animation = animation

        let jointIndexByPath = Self.indexByPath(jointPaths)
        parentIndices = jointPaths.enumerated().map { jointIndex, path in
            guard let separator = path.lastIndex(of: "/"),
                  let parentIndex = jointIndexByPath[String(path[..<separator])],
                  parentIndex < jointIndex
            else { return -1 }
            return parentIndex
        }

        let targetIndexByPath = Self.indexByPath(animation?.paths ?? [])
        animationTargetIndices = jointPaths.map { targetIndexByPath[$0] }
        restDecompositions = self.restTransforms.map(\.decomposed)

        localTransforms = self.restTransforms
        jointTransforms = self.restTransforms
        composeJointTransforms()
    }

    /// The seconds the animation spans; nil without an animation.
    public var timeRange: ClosedRange<Double>? { animation?.timeRange }

    /// Applies the animation at `time`, in seconds, and commits the pose.
    public func setTime(_ time: Double) {
        applyAnimation(at: time)
        commitPose()
    }

    /// Stages the joints the animation drives at `time`, in seconds; the others keep their
    /// staged transforms. Does nothing without an animation.
    public func applyAnimation(at time: Double) {
        guard let animation else { return }
        let sample = animation.sample(at: time)
        for jointIndex in jointPaths.indices {
            guard let targetIndex = animationTargetIndices[jointIndex] else { continue }
            localTransforms[jointIndex] = animation.transform(of: targetIndex, in: sample, fallback: restDecompositions[jointIndex])
        }
    }

    /// Stages joints directly: one local transform per joint, in `jointPaths` order. Joints
    /// past the end of `transforms` keep their staged transforms.
    public func setLocalTransforms(_ transforms: [simd_float4x4]) {
        for jointIndex in jointPaths.indices where jointIndex < transforms.count {
            localTransforms[jointIndex] = transforms[jointIndex]
        }
    }

    /// Composes the staged pose and updates every binding's palette, reading where the anchor
    /// and each mesh sit now. Once per frame: the outgoing pose becomes last frame's.
    public func commitPose() {
        composeJointTransforms()
        let skeletonWorld = anchor?.worldMatrix ?? matrix_identity_float4x4
        for binding in bindings {
            binding.pose(jointTransforms: jointTransforms, skeletonWorld: skeletonWorld)
        }
    }

    /// Binds a geometry whose joint indices refer to `jointPaths` (nil: this skeleton's own
    /// order), drawn by `mesh`. `geometryBindTransform` places the geometry's rest points in
    /// skeleton space at bind time. The binding is posed now, with the last committed pose;
    /// give its palette to the geometry.
    public func bind(device: MTLDevice, mesh: Object?, jointPaths geometryJointPaths: [String]?,
                     geometryBindTransform: simd_float4x4) -> SkeletonBinding {
        let jointIndexByPath = Self.indexByPath(jointPaths)
        let skeletonJointIndices = geometryJointPaths.map { $0.map { jointIndexByPath[$0] ?? -1 } } ?? Array(jointPaths.indices)
        let binding = SkeletonBinding(
            device: device,
            mesh: mesh,
            skeletonJointIndices: skeletonJointIndices,
            inverseBindMatrices: skeletonJointIndices.map { $0 >= 0 ? bindTransforms[$0].inverse * geometryBindTransform : geometryBindTransform },
            geometryBindTransform: geometryBindTransform
        )
        binding.pose(jointTransforms: jointTransforms, skeletonWorld: anchor?.worldMatrix ?? matrix_identity_float4x4)
        bindings.append(binding)
        return binding
    }

    /// Parents come first, so one pass composes every joint with its parent's final transform.
    private func composeJointTransforms() {
        for jointIndex in jointPaths.indices {
            let parentIndex = parentIndices[jointIndex]
            jointTransforms[jointIndex] = parentIndex >= 0 ? jointTransforms[parentIndex] * localTransforms[jointIndex] : localTransforms[jointIndex]
        }
    }

    private static func indexByPath(_ paths: [String]) -> [String: Int] {
        Dictionary(paths.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
