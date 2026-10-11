//
//  AnimationLoader.swift
//  Satin
//

import Foundation
import Metal
import ModelIO
import simd

// Animated assets, through ModelIO: each `MDLSkeleton` becomes a `Skeleton` with its
// animation, each skinned mesh gets a `SkeletonBinding` whose palette its geometry draws with,
// and objects with animated transforms are moved by an `ObjectAnimation`.
//
// TODO(blend-shapes): USD blend shapes are not loaded. ModelIO imports them, but only through
// `MDLMorphDeformer`, a private class (in the binary, not the headers): a mesh component with
// `targetShapes` (MDLMeshes, absolute positions) and `weights` (MDLAnimatedScalarArray, keyed
// from the SkelAnimation). Reachable only by class name and KVC; Apple may change it, and App
// Review may flag it. Needs a decision on private API, a GPU morph step before skinning, and a
// real blend-shape asset.

extension MDLObject {
    /// The skeleton binding a skinned mesh carries; nil for anything else.
    var skeletonBinding: MDLAnimationBindComponent? {
        guard let binding = animationBinding, binding.skeleton != nil else { return nil }
        return binding
    }

    /// The animation binding this object carries, if any: a skinned mesh's (with its skeleton),
    /// or a skeleton's own (naming only its animation).
    var animationBinding: MDLAnimationBindComponent? {
        components.compactMap { $0 as? MDLAnimationBindComponent }.first
    }
}

/// Binds each skinned mesh to its skeleton, making one `Skeleton` per skeleton and animation
/// in the asset, anchored where its skeleton prim sits and posed at `startTime` (or its own
/// animation's start) before binding, so palettes start still. `startPoseOnly` reads just that
/// pose of each animation.
///
/// As UsdSkel resolves it, a mesh's animation is the one its own binding names, else its
/// skeleton's: files place `skel:animationSource` on either. Meshes sharing a skeleton but not
/// an animation get separate `Skeleton`s.
func bindSkeletons(record: AssetLoadRecord, device: MTLDevice, startTime: Double?, startPoseOnly: Bool) -> [Skeleton] {
    var loaded: [(source: MDLSkeleton, animation: MDLPackedJointAnimation?, skeleton: Skeleton)] = []

    for (mesh, mdlMesh) in record.skinnedMeshes {
        guard let binding = mdlMesh.skeletonBinding, let mdlSkeleton = binding.skeleton else { continue }
        let animation = (binding.jointAnimation ?? mdlSkeleton.animationBinding?.jointAnimation) as? MDLPackedJointAnimation
        let skeleton: Skeleton
        if let existing = loaded.first(where: { $0.source === mdlSkeleton && $0.animation === animation }) {
            skeleton = existing.skeleton
        } else {
            skeleton = loadSkeleton(mdlSkeleton, animation: animation, anchor: record.skeletonAnchors[ObjectIdentifier(mdlSkeleton)],
                                    startTime: startTime, startPoseOnly: startPoseOnly)
            if let start = startTime ?? skeleton.timeRange?.lowerBound { skeleton.setTime(start) }
            loaded.append((mdlSkeleton, animation, skeleton))
        }
        let skeletonBinding = skeleton.bind(
            device: device,
            mesh: mesh,
            jointPaths: binding.jointPaths,
            geometryBindTransform: floatMatrix(binding.geometryBindTransform)
        )
        mesh.geometry.jointPalette = skeletonBinding.palette
    }
    return loaded.map(\.skeleton)
}

func loadSkeleton(_ mdlSkeleton: MDLSkeleton, animation: MDLPackedJointAnimation?, anchor: Object?, startTime: Double?, startPoseOnly: Bool) -> Skeleton {
    Skeleton(
        jointPaths: mdlSkeleton.jointPaths,
        restTransforms: mdlSkeleton.jointRestTransforms.float4x4Array,
        bindTransforms: mdlSkeleton.jointBindTransforms.float4x4Array,
        animation: animation.map { loadJointAnimation($0, startTime: startTime, startPoseOnly: startPoseOnly) },
        anchor: anchor
    )
}

/// Every key of every channel, read once into flat storage, so posing never calls into
/// ModelIO. `startPoseOnly` reads one key per channel, at `startTime` or the earliest key.
func loadJointAnimation(_ packed: MDLPackedJointAnimation, startTime: Double?, startPoseOnly: Bool) -> TransformAnimation {
    let channelTimes = [packed.translations, packed.rotations, packed.scales].map { $0.keyTimes.map(\.doubleValue) }
    let earliest = channelTimes.compactMap(\.first).min()
    func keyTimes(_ times: [Double]) -> [Double] {
        guard startPoseOnly, !times.isEmpty, let start = startTime ?? earliest else { return times }
        return [start]
    }
    let translationTimes = keyTimes(channelTimes[0])
    let rotationTimes = keyTimes(channelTimes[1])
    let scaleTimes = keyTimes(channelTimes[2])
    let targetCount = packed.jointPaths.count
    return TransformAnimation(
        paths: packed.jointPaths,
        translations: .init(keyTimes: translationTimes, values: translationTimes.flatMap { packed.translations.float3Array(atTime: $0) }, targetCount: targetCount),
        rotations: .init(keyTimes: rotationTimes, values: rotationTimes.flatMap { packed.rotations.floatQuaternionArray(atTime: $0) }, targetCount: targetCount),
        scales: .init(keyTimes: scaleTimes, values: scaleTimes.flatMap { packed.scales.float3Array(atTime: $0) }, targetCount: targetCount)
    )
}

/// The animated objects' local transforms, sampled at every frame of the asset and at every
/// object's own keys. Sampled this densely, interpolating between samples closely follows the
/// file's own interpolation of its transform operations (Euler angles, pivots), and is exact at
/// each sample. `startPoseOnly` samples once, at `startTime` or the earliest key. Nil without
/// animated objects.
func loadObjectAnimation(animatedObjects: [(object: Object, mdlObject: MDLObject)], asset: MDLAsset,
                         startTime: Double?, startPoseOnly: Bool) -> ObjectAnimation? {
    guard !animatedObjects.isEmpty else { return nil }
    var keyTimes = Set(animatedObjects.flatMap { $0.mdlObject.transform?.keyTimes.map(\.doubleValue) ?? [] })
    if asset.frameInterval > 0, asset.endTime > asset.startTime {
        let frameCount = Int(((asset.endTime - asset.startTime) / asset.frameInterval).rounded())
        for frame in 0 ... frameCount {
            keyTimes.insert(asset.startTime + Double(frame) * asset.frameInterval)
        }
    }
    var sortedKeyTimes = keyTimes.sorted()
    if startPoseOnly, let start = startTime ?? sortedKeyTimes.first {
        sortedKeyTimes = [start]
    }

    // Key-major, as `TransformAnimation.Channel` stores values.
    let components = sortedKeyTimes.flatMap { time in
        animatedObjects.map { TransformComponents(matrix: $0.mdlObject.transform?.localTransform?(atTime: time) ?? matrix_identity_float4x4) }
    }
    let targetCount = animatedObjects.count
    let animation = TransformAnimation(
        paths: animatedObjects.map(\.mdlObject.path),
        translations: .init(keyTimes: sortedKeyTimes, values: components.map(\.translation), targetCount: targetCount),
        rotations: .init(keyTimes: sortedKeyTimes, values: components.map(\.rotation), targetCount: targetCount),
        scales: .init(keyTimes: sortedKeyTimes, values: components.map(\.scale), targetCount: targetCount)
    )
    return ObjectAnimation(objects: animatedObjects.map(\.object), animation: animation)
}

/// Each vertex's joint influences in the layout Satin skins with: the four strongest of
/// however many the file gives, renormalized, as UShort4 indices and Float4 weights. Indices
/// may be any integer format; weights must be float. Vertices no listed joint moves stay where
/// they were bound, through the binding's rest joint (`SkeletonBinding.restJointIndex`).
func loadJointInfluences(mdlMesh: MDLMesh, geometry: Geometry) {
    guard let indexData = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeJointIndices),
          let weightData = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeJointWeights),
          let binding = mdlMesh.skeletonBinding, let skeleton = binding.skeleton
    else { return }
    // The geometry's joints, in the order its indices use; the rest joint follows them.
    let jointCount = binding.jointPaths?.count ?? skeleton.jointPaths.count

    let influenceCount = vertexFormatComponentCount(indexData.format)
    let indexByteCount = vertexFormatIntegerByteCount(indexData.format)
    guard influenceCount > 0, vertexFormatComponentCount(weightData.format) == influenceCount,
          weightData.format.rawValue & vertexFormatKindMask == MDLVertexFormat.float.rawValue & vertexFormatKindMask,
          indexByteCount > 0
    else {
        print("Joint influences not supported: indices \(indexData.format.rawValue), weights \(weightData.format.rawValue)")
        return
    }

    let vertexCount = mdlMesh.vertexCount
    var jointIndices = [simd_ushort4](repeating: .zero, count: vertexCount)
    var jointWeights = [simd_float4](repeating: .zero, count: vertexCount)
    var vertexIndices = [Int](repeating: 0, count: influenceCount)
    var vertexWeights = [Float](repeating: 0, count: influenceCount)

    let indexStart = UnsafeRawPointer(indexData.dataStart)
    let weightStart = UnsafeRawPointer(weightData.dataStart)
    for vertex in 0 ..< vertexCount {
        let indexOffset = vertex * indexData.stride
        let weightOffset = vertex * weightData.stride
        for influence in 0 ..< influenceCount {
            let byteOffset = indexOffset + influence * indexByteCount
            switch indexByteCount {
            case 1: vertexIndices[influence] = Int(indexStart.loadUnaligned(fromByteOffset: byteOffset, as: UInt8.self))
            case 2: vertexIndices[influence] = Int(indexStart.loadUnaligned(fromByteOffset: byteOffset, as: UInt16.self))
            default: vertexIndices[influence] = Int(indexStart.loadUnaligned(fromByteOffset: byteOffset, as: UInt32.self))
            }
            vertexWeights[influence] = weightStart.loadUnaligned(fromByteOffset: weightOffset + influence * MemoryLayout<Float>.size, as: Float.self)
        }
        (jointIndices[vertex], jointWeights[vertex]) = strongestJointInfluences(indices: vertexIndices, weights: vertexWeights, jointCount: jointCount)
    }

    geometry.addAttribute(UShort4BufferAttribute(defaultValue: .zero, data: jointIndices), for: .JointIndices)
    geometry.addAttribute(Float4BufferAttribute(defaultValue: .zero, data: jointWeights), for: .JointWeights)
}

/// The four strongest positive influences on joints `0 ..< jointCount`, strongest first, with
/// weights renormalized to sum to one; earlier influences win ties. Indices outside the joints
/// are dropped, since the GPU would read past the palette. A vertex left with no weight goes
/// to the rest joint, index `jointCount`, and stays where it was bound.
func strongestJointInfluences(indices: [Int], weights: [Float], jointCount: Int) -> (indices: simd_ushort4, weights: simd_float4) {
    let restJointIndex = UInt16(clamping: jointCount)
    var strongestIndices = simd_ushort4.zero
    var strongestWeights = simd_float4.zero
    for (index, weight) in zip(indices, weights) where weight > 0 && index >= 0 && index < min(jointCount, Int(UInt16.max)) {
        var slot = 4
        while slot > 0 && strongestWeights[slot - 1] < weight { slot -= 1 }
        guard slot < 4 else { continue }
        for shifted in stride(from: 3, to: slot, by: -1) {
            strongestIndices[shifted] = strongestIndices[shifted - 1]
            strongestWeights[shifted] = strongestWeights[shifted - 1]
        }
        strongestIndices[slot] = UInt16(index)
        strongestWeights[slot] = weight
    }
    let total = strongestWeights.sum()
    guard total > 0 else { return (simd_ushort4(restJointIndex, 0, 0, 0), simd_float4(1, 0, 0, 0)) }
    return (strongestIndices, strongestWeights / total)
}

private func floatMatrix(_ matrix: simd_double4x4) -> simd_float4x4 {
    simd_float4x4(simd_float4(matrix.columns.0), simd_float4(matrix.columns.1), simd_float4(matrix.columns.2), simd_float4(matrix.columns.3))
}

// MDLVertexFormat packs its scalar kind in the high bits and its component count in the low.
private let vertexFormatKindMask: UInt = 0xFF0000

private func vertexFormatComponentCount(_ format: MDLVertexFormat) -> Int {
    format.rawValue & 0x1000 == 0 ? Int(format.rawValue & 0xFF) : 0
}

/// Bytes per component for integer formats; 0 for anything else.
private func vertexFormatIntegerByteCount(_ format: MDLVertexFormat) -> Int {
    switch format.rawValue & vertexFormatKindMask {
    case MDLVertexFormat.uChar.rawValue & vertexFormatKindMask, MDLVertexFormat.char.rawValue & vertexFormatKindMask: return 1
    case MDLVertexFormat.uShort.rawValue & vertexFormatKindMask, MDLVertexFormat.short.rawValue & vertexFormatKindMask: return 2
    case MDLVertexFormat.uInt.rawValue & vertexFormatKindMask, MDLVertexFormat.int.rawValue & vertexFormatKindMask: return 4
    default: return 0
    }
}
