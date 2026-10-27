//
//  Loader.swift
//  Satin
//
//  Created by Reza Ali on 4/3/23.
//

import Foundation
import Metal
import MetalKit
import ModelIO

#if SWIFT_PACKAGE
import SatinCore
#endif

/// A loaded model with everything in it that moves over time.
public struct LoadedAsset {
    /// The model's hierarchy, as the file lays it out, except that skinned meshes sit where
    /// their skeletons do.
    public let root: Object
    /// Its skeletons and animated objects on one clock; nil when nothing in it moves.
    public let animation: AssetAnimation?
}

/// Loads a model with its hierarchy and animation: skinned meshes bound to their skeletons,
/// and animated objects. Posed at the start of its animation.
///
/// `instanced` loads each mesh as an `InstancedMesh` of one instance, where it sits, to draw
/// the model several times; instance matrices apply in each mesh's own space.
///
/// `mergeStaticMeshes` joins meshes that draw alike into one mesh each (see
/// `mergeStaticMeshes(_:cellsAlongLongestSide:context:textureLoader:record:)`), only within each of a
/// grid of `mergeCells` cells along the model's longest side, so culling can still skip what is
/// out of view; 1 merges across the whole model. Fewer draws, the same pixels, but the
/// joined meshes no longer exist on their own. Ignored when `instanced`.
public func loadAnimatedAsset(url: URL, context: Context, textureLoader: MTKTextureLoader? = nil, instanced: Bool = false, mergeStaticMeshes: Bool = false, mergeCells: Int = 4) -> LoadedAsset {
    loadAssetHierarchy(url: url, context: context, textureLoader: textureLoader, startPoseOnly: false, instanced: instanced, mergeStaticMeshes: mergeStaticMeshes, mergeCells: mergeCells)
}

/// Loads a model as its meshes, each placed by its world transform, posed at the start of its
/// animation. Only that pose is read from the animation. `mergeStaticMeshes` and `mergeCells` as
/// for `loadAnimatedAsset`.
public func loadAsset(url: URL, context: Context, textureLoader: MTKTextureLoader? = nil, mergeStaticMeshes: Bool = false, mergeCells: Int = 4) -> Object? {
    Object.flatten(loadAssetHierarchy(url: url, context: context, textureLoader: textureLoader, startPoseOnly: true, mergeStaticMeshes: mergeStaticMeshes, mergeCells: mergeCells).root)
}

/// What one pass over an asset's objects collects for skinning and animation.
struct AssetLoadRecord {
    var skinnedMeshes: [(mesh: Mesh, mdlMesh: MDLMesh)] = []
    var animatedObjects: [(object: Object, mdlObject: MDLObject)] = []
    /// The object standing for each skeleton prim, by its ModelIO object: where that
    /// skeleton's space sits in the scene, and so where its skinned meshes go.
    var skeletonAnchors: [ObjectIdentifier: Object] = [:]
    /// The materials and textures this load has made, shared between equivalent sources.
    let materials = LoadedMaterials()
    /// The meshes that may merge, in load order, each standing in the hierarchy as a placeholder
    /// until merging decides what replaces it.
    var mergeCandidates: [MergeCandidate] = []
}

/// The model's hierarchy and animation, posed at its start. `startPoseOnly` reads just that
/// pose, for a model that will not be animated.
func loadAssetHierarchy(url: URL, context: Context, textureLoader: MTKTextureLoader?, startPoseOnly: Bool, instanced: Bool = false, mergeStaticMeshes merges: Bool = false, mergeCells: Int = 4) -> LoadedAsset {
    let asset = MDLAsset(url: url)
    if textureLoader != nil { asset.loadTextures() }

    let root = Object(context: context, label: url.deletingPathExtension().lastPathComponent)
    var record = AssetLoadRecord()
    loadAssetChildren(parent: root, children: (0 ..< asset.count).map { asset.object(at: $0) }, context: context,
                      textureLoader: textureLoader, instanced: instanced, mergesStaticMeshes: merges && !instanced,
                      underAnimation: false, record: &record)
    // Candidates are static, so their world transforms are final once the hierarchy is built.
    mergeStaticMeshes(record.mergeCandidates, cellsAlongLongestSide: mergeCells, context: context, textureLoader: textureLoader, record: record)

    let assetTimeRange = asset.endTime > asset.startTime ? asset.startTime ... asset.endTime : nil
    // Objects first: animated objects take their start pose before skeletons take theirs.
    let objectAnimation = loadObjectAnimation(animatedObjects: record.animatedObjects, asset: asset,
                                              startTime: assetTimeRange?.lowerBound, startPoseOnly: startPoseOnly)
    if let objectAnimation, let start = assetTimeRange?.lowerBound ?? objectAnimation.timeRange?.lowerBound {
        objectAnimation.setTime(start)
    }
    let skeletons = bindSkeletons(record: record, root: root, device: context.device, startTime: assetTimeRange?.lowerBound, startPoseOnly: startPoseOnly)
    // World transforms are final only now, with the hierarchy built and posed.
    flipWindingOfMirroredMeshes(in: root)
    guard !skeletons.isEmpty || objectAnimation != nil else { return LoadedAsset(root: root, animation: nil) }
    return LoadedAsset(root: root, animation: AssetAnimation(skeletons: skeletons, objectAnimation: objectAnimation, timeRange: assetTimeRange))
}

/// `generatesNormals` false for a mesh whose normals `generateNormals` already made.
func loadMesh(mdlMesh: MDLMesh, context: Context, textureLoader: MTKTextureLoader?, instanced: Bool, materials: LoadedMaterials, generatesNormals: Bool = true) -> Mesh {
    let geometry = Geometry(context: context)
    let stnMesh = instanced
        ? InstancedMesh(context: context, label: mdlMesh.name, geometry: geometry, material: nil, count: 1)
        : Mesh(context: context, label: mdlMesh.name, geometry: geometry, material: nil)

    if generatesNormals { generateNormals(mdlMesh) }

    let descriptor = mdlMesh.vertexDescriptor

    var bufferInterleaved: [Int: Bool] = [:]
    var bufferIndexMap: [Int: VertexBufferIndex] = [:]
    var bufferIndexAttributes: [Int: [MDLVertexAttribute]] = [:]

    for i in 0 ..< descriptor.attributes.count {
        if let attribute = descriptor.attributes.object(at: i) as? MDLVertexAttribute, attribute.format != .invalid {
            let bufferIndex = attribute.bufferIndex

            if bufferInterleaved[bufferIndex] != nil {
                bufferInterleaved[bufferIndex] = true
                bufferIndexMap[bufferIndex] = .Vertices
                bufferIndexAttributes[bufferIndex, default: []].append(attribute)
            }
            else {
                bufferInterleaved[bufferIndex] = false
                // Nil for attributes Satin does not render; their buffers are skipped below.
                bufferIndexMap[bufferIndex] = VertexAttributeIndex(name: attribute.name)?.bufferIndex
                bufferIndexAttributes[bufferIndex] = [attribute]
            }
        }
    }

    let count = mdlMesh.vertexCount
    for (bufferIndex, vertexBuffer) in mdlMesh.vertexBuffers.enumerated() where count > 0 {
        guard let index = bufferIndexMap[bufferIndex],
              let interleaved = bufferInterleaved[bufferIndex],
              let attributes = bufferIndexAttributes[bufferIndex]
        else { continue }
        let stride = vertexBuffer.length / count
        let bytes = vertexBuffer.map().bytes

        if interleaved {
            let parent = InterleavedBuffer(index: index, data: bytes, stride: stride, count: count, source: vertexBuffer)

            for attribute in attributes {
                let offset = attribute.offset
                guard let attributeIndex = VertexAttributeIndex(name: attribute.name) else {
                    print("Vertex attribute not supported: \(attribute.name)")
                    continue
                }
                // Loaded by `loadJointInfluences`, in the layout Satin skins with.
                if attributeIndex == .JointIndices || attributeIndex == .JointWeights { continue }
                switch attribute.format {
                    case .float4:
                        geometry.addAttribute(
                            Float4InterleavedBufferAttribute(
                                parent: parent,
                                offset: offset
                            ), for: attributeIndex
                        )
                    case .float3:
                        geometry.addAttribute(
                            Float3InterleavedBufferAttribute(
                                parent: parent,
                                offset: offset
                            ), for: attributeIndex
                        )
                    case .float2:
                        geometry.addAttribute(
                            Float2InterleavedBufferAttribute(
                                parent: parent,
                                offset: offset
                            ), for: attributeIndex
                        )
                    case .float:
                        geometry.addAttribute(
                            FloatInterleavedBufferAttribute(
                                parent: parent,
                                offset: offset
                            ), for: attributeIndex
                        )
                    default:
                        print("Format not supported: \(attribute.name), \(attribute.format)")
                }
            }
        }
        else {
            for attribute in attributes {
                guard let attributeIndex = VertexAttributeIndex(name: attribute.name) else {
                    print("Vertex attribute not supported: \(attribute.name)")
                    continue
                }
                // Loaded by `loadJointInfluences`, in the layout Satin skins with.
                if attributeIndex == .JointIndices || attributeIndex == .JointWeights { continue }
                switch attribute.format {
                    case .float4:
                        let ptr = bytes.bindMemory(to: simd_float4.self, capacity: count)
                        let data = Array(UnsafeBufferPointer(start: ptr, count: count))
                        geometry.addAttribute(
                            Float4BufferAttribute(defaultValue: .one, data: data), for: attributeIndex
                        )
                    case .float3:
                        if stride == MemoryLayout<MTLPackedFloat3>.stride {
                            let ptr = bytes.bindMemory(to: MTLPackedFloat3.self, capacity: count)
                            let data = Array(UnsafeBufferPointer(start: ptr, count: count))
                            geometry.addAttribute(
                                PackedFloat3BufferAttribute(defaultValue: MTLPackedFloat3Make(0, 0, 0), data: data), for: attributeIndex
                            )
                        }
                        else if stride == MemoryLayout<simd_float3>.stride {
                            let ptr = bytes.bindMemory(to: simd_float3.self, capacity: count)
                            let data = Array(UnsafeBufferPointer(start: ptr, count: count))
                            geometry.addAttribute(
                                Float3BufferAttribute(defaultValue: .zero, data: data), for: attributeIndex
                            )
                        }
                    case .float2:
                        let ptr = bytes.bindMemory(to: simd_float2.self, capacity: count)
                        let data = Array(UnsafeBufferPointer(start: ptr, count: count))
                        geometry.addAttribute(
                            Float2BufferAttribute(defaultValue: .zero, data: data), for: attributeIndex
                        )
                    case .float:
                        let ptr = bytes.bindMemory(to: Float.self, capacity: count)
                        let data = Array(UnsafeBufferPointer(start: ptr, count: count))
                        geometry.addAttribute(
                            FloatBufferAttribute(defaultValue: .zero, data: data), for: attributeIndex
                        )
                    default:
                        print("Format not supported: \(attribute.name), \(attribute.format)")
                }
            }
        }
    }

    loadJointInfluences(mdlMesh: mdlMesh, geometry: geometry)

    if let submeshes = mdlMesh.submeshes {
        if submeshes.count > 1 {
            for submeshIndex in 0 ..< submeshes.count {
                if let mdlSubmesh = submeshes.object(at: submeshIndex) as? MDLSubmesh {
                    if mdlSubmesh.geometryType == .triangles {
                        let indexCount = mdlSubmesh.indexCount
                        let indexBuffer = mdlSubmesh.indexBuffer(asIndexType: .uInt32)
                        let indexBytes = indexBuffer.map().bytes.bindMemory(to: UInt32.self, capacity: indexCount)

                        var material: Material?
                        if let mdlMaterial = mdlSubmesh.material, let textureLoader = textureLoader {
                            material = materials.material(for: mdlMaterial, context: context, textureLoader: textureLoader)
                        }

                        stnMesh.addSubmesh(
                            Submesh(
                                context: context,
                                label: mdlSubmesh.name,
                                elementBuffer: ElementBuffer(
                                    type: .uint32,
                                    data: indexBytes,
                                    count: indexCount,
                                    source: indexBuffer
                                ),
                                material: material
                            )
                        )
                    }
                }
            }
        }
        else {
            if let mdlSubmesh = submeshes.object(at: 0) as? MDLSubmesh {
                if let mdlMaterial = mdlSubmesh.material, let textureLoader = textureLoader {
                    stnMesh.material = materials.material(for: mdlMaterial, context: context, textureLoader: textureLoader)
                }
                let indexBuffer = mdlSubmesh.indexBuffer(asIndexType: .uInt32)
                geometry.setElements(
                    ElementBuffer(
                        type: .uint32,
                        data: indexBuffer.map().bytes,
                        count: mdlSubmesh.indexCount,
                        source: indexBuffer
                    )
                )
            }
        }
    }

    // USD's sidedness arrives on each submesh's material (ModelIO's materialFace).
    var faces: [MDLMaterialFace] = []
    for case let mdlSubmesh as MDLSubmesh in mdlMesh.submeshes ?? [] {
        if let mdlMaterial = mdlSubmesh.material { faces.append(mdlMaterial.materialFace) }
    }
    stnMesh.cullMode = cullMode(forFaces: faces)

    return stnMesh
}

/// Normals as every loaded mesh gets them.
func generateNormals(_ mdlMesh: MDLMesh) {
    // 0.1 appears to fix USD import issues with parts of sponza model...
    mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.1)
}

/// `underAnimation`: an ancestor of `children` has an animated transform.
func loadAssetChildren(parent: Object, children: [MDLObject], context: Context, textureLoader: MTKTextureLoader?,
                       instanced: Bool, mergesStaticMeshes: Bool, underAnimation: Bool, record: inout AssetLoadRecord) {
    for child in children {
        let object: Object
        let isAnimated = underAnimation || (child.transform?.keyTimes.count ?? 0) > 1
        if mergesStaticMeshes, !isAnimated, let mdlMesh = child as? MDLMesh,
           let candidate = MergeCandidate(mdlMesh: mdlMesh, context: context, textureLoader: textureLoader, materials: record.materials) {
            record.mergeCandidates.append(candidate)
            object = candidate.placeholder
        }
        else if let mdlMesh = child as? MDLMesh {
            let mesh = loadMesh(mdlMesh: mdlMesh, context: context, textureLoader: textureLoader, instanced: instanced, materials: record.materials)
            if mdlMesh.skeletonBinding != nil { record.skinnedMeshes.append((mesh, mdlMesh)) }
            object = mesh
        }
        else {
            object = Object(context: context, label: child.name)
            if child is MDLSkeleton { record.skeletonAnchors[ObjectIdentifier(child)] = object }
        }

        if let transform = child.transform {
            object.localMatrix = transform.matrix
            // A skinned mesh's own transform does not place its skin (UsdSkel): it moves to its
            // skeleton when bound, so nothing animates it.
            let isSkinned = (child as? MDLMesh)?.skeletonBinding != nil
            if transform.keyTimes.count > 1, !isSkinned { record.animatedObjects.append((object, child)) }
        }
        parent.add(object)
        loadAssetChildren(parent: object, children: child.children.objects, context: context, textureLoader: textureLoader,
                          instanced: instanced, mergesStaticMeshes: mergesStaticMeshes, underAnimation: isAnimated, record: &record)
    }
}

// MARK: - Merging Static Meshes

/// A mesh that may merge with others: static, unskinned, childless, one triangle submesh with an
/// opaque material. Built only once merging decides what it joins; until then a placeholder holds
/// its place in the hierarchy.
struct MergeCandidate {
    let mdlMesh: MDLMesh
    let submesh: MDLSubmesh
    let material: Material
    let cullMode: MTLCullMode
    let placeholder: Object
    /// Whether its vertex buffers hold exactly its vertices, so they concatenate as they are.
    /// A candidate that can't join still loads from here, as a group of one.
    let canJoin: Bool

    init?(mdlMesh: MDLMesh, context: Context, textureLoader: MTKTextureLoader?, materials: LoadedMaterials) {
        guard mdlMesh.skeletonBinding == nil, mdlMesh.children.objects.isEmpty,
              let submeshes = mdlMesh.submeshes, submeshes.count == 1,
              let submesh = submeshes.object(at: 0) as? MDLSubmesh, submesh.geometryType == .triangles,
              let mdlMaterial = submesh.material, let textureLoader
        else { return nil }
        let material = materials.material(for: mdlMaterial, context: context, textureLoader: textureLoader)
        guard material.blending == .disabled else { return nil }

        // Normals now, as loading would make them, so layouts compare as they will load.
        generateNormals(mdlMesh)
        canJoin = Self.hasConcatenableBuffers(mdlMesh)

        self.mdlMesh = mdlMesh
        self.submesh = submesh
        self.material = material
        cullMode = Satin.cullMode(forFaces: [mdlMaterial.materialFace])
        placeholder = Object(context: context, label: mdlMesh.name)
    }

    /// Whether `other` draws exactly as this does: one material, cull mode, world transform and
    /// vertex layout. Anything else, such as the draw's motion or bounds, may differ.
    func drawsAlike(_ other: MergeCandidate) -> Bool {
        canJoin && other.canJoin
            && material === other.material
            && cullMode == other.cullMode
            && placeholder.worldMatrix == other.placeholder.worldMatrix
            && Self.haveSameVertexLayout(mdlMesh, other.mdlMesh)
    }

    /// Whether each vertex buffer holds exactly its vertices, so buffers concatenate as they are.
    private static func hasConcatenableBuffers(_ mdlMesh: MDLMesh) -> Bool {
        guard mdlMesh.vertexCount > 0 else { return false }
        for (bufferIndex, buffer) in mdlMesh.vertexBuffers.enumerated() {
            guard bufferIndex < mdlMesh.vertexDescriptor.layouts.count,
                  let layout = mdlMesh.vertexDescriptor.layouts[bufferIndex] as? MDLVertexBufferLayout,
                  layout.stride > 0, buffer.length == layout.stride * mdlMesh.vertexCount
            else { return false }
        }
        return true
    }

    private static func haveSameVertexLayout(_ first: MDLMesh, _ second: MDLMesh) -> Bool {
        let firstDescriptor = first.vertexDescriptor
        let secondDescriptor = second.vertexDescriptor
        guard first.vertexBuffers.count == second.vertexBuffers.count,
              firstDescriptor.attributes.count == secondDescriptor.attributes.count,
              firstDescriptor.layouts.count == secondDescriptor.layouts.count
        else { return false }
        for index in 0 ..< firstDescriptor.attributes.count {
            guard let firstAttribute = firstDescriptor.attributes[index] as? MDLVertexAttribute,
                  let secondAttribute = secondDescriptor.attributes[index] as? MDLVertexAttribute,
                  firstAttribute.name == secondAttribute.name, firstAttribute.format == secondAttribute.format,
                  firstAttribute.offset == secondAttribute.offset, firstAttribute.bufferIndex == secondAttribute.bufferIndex
            else { return false }
        }
        for index in 0 ..< firstDescriptor.layouts.count {
            guard let firstLayout = firstDescriptor.layouts[index] as? MDLVertexBufferLayout,
                  let secondLayout = secondDescriptor.layouts[index] as? MDLVertexBufferLayout,
                  firstLayout.stride == secondLayout.stride
            else { return false }
        }
        return true
    }
}

/// Joins `candidates` that draw alike into one mesh per group, in load order: each group is
/// built where its first member sat, from the members' vertices as they are and their indices in
/// member order, and the other members' places are removed. A group of one loads as it would
/// unmerged. Deterministic: the same file merges the same way.
///
/// Pixels stay the same: the joined meshes share material, cull mode and world transform, so
/// each vertex and the matrix it is drawn with are unchanged, and only opaque meshes join, whose
/// result doesn't depend on draw order. (Exactly coplanar, overlapping surfaces of different
/// materials can tie in depth either way; draw order decides those.)
///
/// Groups never span cells of a grid laid over the candidates' world bounds, `cellsAlongLongestSide`
/// cells along the longest side and as many cells of that size along the others. A candidate falls
/// in the cell holding its bounds' centre: merged meshes stay mostly local, which helps culling, but
/// a mesh can extend past its cell, so this is a locality heuristic, not a bound.
func mergeStaticMeshes(_ candidates: [MergeCandidate], cellsAlongLongestSide: Int, context: Context, textureLoader: MTKTextureLoader?, record: AssetLoadRecord) {
    let cells = mergeCells(of: candidates, cellsAlongLongestSide: cellsAlongLongestSide)
    var groups: [(members: [MergeCandidate], vertexCount: Int, cell: SIMD3<Int32>)] = []
    for (candidateIndex, candidate) in candidates.enumerated() {
        var joined = false
        for groupIndex in groups.indices where groups[groupIndex].cell == cells[candidateIndex] && groups[groupIndex].members[0].drawsAlike(candidate) {
            guard candidate.mdlMesh.vertexCount <= Int(UInt32.max) - groups[groupIndex].vertexCount else { continue }
            groups[groupIndex].members.append(candidate)
            groups[groupIndex].vertexCount += candidate.mdlMesh.vertexCount
            joined = true
            break
        }
        if !joined { groups.append((members: [candidate], vertexCount: candidate.mdlMesh.vertexCount, cell: cells[candidateIndex])) }
    }

    for group in groups {
        let members = group.members
        let mdlMesh = members.count == 1 ? members[0].mdlMesh : mergedMesh(members)
        let mesh = loadMesh(mdlMesh: mdlMesh, context: context, textureLoader: textureLoader, instanced: false,
                            materials: record.materials, generatesNormals: false)
        replace(members[0].placeholder, with: mesh)
        for member in members.dropFirst() {
            member.placeholder.removeFromParent()
        }
    }
}

/// The grid cell each of `candidates` falls in, by the centre of its world bounds.
private func mergeCells(of candidates: [MergeCandidate], cellsAlongLongestSide: Int) -> [SIMD3<Int32>] {
    var worldBounds: [Bounds] = []
    worldBounds.reserveCapacity(candidates.count)
    var modelBounds = createBounds()
    for candidate in candidates {
        let box = candidate.mdlMesh.boundingBox
        let bounds = transformBounds(Bounds(min: box.minBounds, max: box.maxBounds), candidate.placeholder.worldMatrix)
        worldBounds.append(bounds)
        modelBounds = mergeBounds(modelBounds, bounds)
    }

    let extent = modelBounds.max - modelBounds.min
    let longestSide = max(extent.x, extent.y, extent.z)
    guard cellsAlongLongestSide > 1, longestSide.isFinite, longestSide > 0 else {
        return [SIMD3<Int32>](repeating: .zero, count: candidates.count)
    }
    let cellSize = longestSide / Float(cellsAlongLongestSide)
    let lastCell = SIMD3<Float>(repeating: Float(cellsAlongLongestSide - 1))
    return worldBounds.map { bounds in
        let centre = (bounds.min + bounds.max) * 0.5
        let cell = simd_clamp(((centre - modelBounds.min) / cellSize).rounded(.down), .zero, lastCell)
        return SIMD3<Int32>(cell, rounding: .towardZero)
    }
}

/// One mesh of `members`' vertices, buffer by buffer in member order, and their indices, each
/// member's moved past the vertices before it. Named and bound as the first member.
private func mergedMesh(_ members: [MergeCandidate]) -> MDLMesh {
    let first = members[0]
    var vertexBuffers: [MDLMeshBuffer] = []
    for bufferIndex in first.mdlMesh.vertexBuffers.indices {
        var data = Data()
        for member in members {
            let buffer = member.mdlMesh.vertexBuffers[bufferIndex]
            let map = buffer.map()
            data.append(map.bytes.assumingMemoryBound(to: UInt8.self), count: buffer.length)
        }
        vertexBuffers.append(MDLMeshBufferData(type: .vertex, data: data))
    }

    var indices: [UInt32] = []
    var vertexBase: UInt32 = 0
    for member in members {
        let indexCount = member.submesh.indexCount
        let indexBuffer = member.submesh.indexBuffer(asIndexType: .uInt32)
        let map = indexBuffer.map()
        let memberIndices = map.bytes.bindMemory(to: UInt32.self, capacity: indexCount)
        for index in 0 ..< indexCount {
            indices.append(memberIndices[index] + vertexBase)
        }
        vertexBase += UInt32(member.mdlMesh.vertexCount)
    }

    let submesh = MDLSubmesh(
        name: first.submesh.name,
        indexBuffer: MDLMeshBufferData(type: .index, data: indices.withUnsafeBytes { Data($0) }),
        indexCount: indices.count,
        indexType: .uInt32,
        geometryType: .triangles,
        material: first.submesh.material
    )
    let mesh = MDLMesh(
        vertexBuffers: vertexBuffers,
        vertexCount: Int(vertexBase),
        descriptor: MDLVertexDescriptor(vertexDescriptor: first.mdlMesh.vertexDescriptor),
        submeshes: [submesh]
    )
    mesh.name = first.mdlMesh.name
    return mesh
}

/// Puts `object` where `placeholder` is, with its local transform.
private func replace(_ placeholder: Object, with object: Object) {
    object.localMatrix = placeholder.localMatrix
    guard let parent = placeholder.parent,
          let index = parent.children.firstIndex(where: { $0 === placeholder })
    else { return }
    parent.insert(object, at: index)
    parent.remove(placeholder)
}

// MARK: - Sidedness

/// The cull mode for a mesh whose submesh materials face `faces`. Culling is mesh-wide, so any
/// double-sided submesh, or a mix of front- and back-facing ones, culls nothing; so does a mesh
/// with no materials, which says nothing about its sides.
func cullMode(forFaces faces: [MDLMaterialFace]) -> MTLCullMode {
    guard let first = faces.first, faces.allSatisfy({ $0 == first }) else { return .none }
    switch first {
    case .front: return .back
    case .back: return .front
    case .doubleSided: return .none
    @unknown default: return .none
    }
}

/// Flips the winding of every mesh under `root` whose world transform mirrors it (a negative
/// determinant), so back-face culling keeps its outside faces. Only the transforms as loaded: a
/// mirror applied later is the caller's to handle.
func flipWindingOfMirroredMeshes(in root: Object) {
    for case let mesh as Mesh in root.getChildren() {
        let world = mesh.worldMatrix
        let linear = simd_float3x3(simd_make_float3(world.columns.0), simd_make_float3(world.columns.1), simd_make_float3(world.columns.2))
        if simd_determinant(linear) < 0 {
            mesh.windingOrder = mesh.windingOrder == .clockwise ? .counterClockwise : .clockwise
        }
    }
}

// MARK: - Shared Materials and Textures

/// The textures one load has made, by source and loading options: an image several materials
/// use, loaded the same way, loads once. The same image loaded with other options (mipmaps or
/// not) is a different texture.
final class LoadedTextures {
    private var entries: [(source: String, generateMipmaps: Bool, origin: String, texture: MTLTexture)] = []

    func texture(source: String, options: [MTKTextureLoader.Option: Any]) -> MTLTexture? {
        let generateMipmaps = Self.generateMipmaps(options)
        let origin = Self.origin(options)
        for entry in entries where entry.source == source && entry.generateMipmaps == generateMipmaps && entry.origin == origin {
            return entry.texture
        }
        return nil
    }

    func add(_ texture: MTLTexture, source: String, options: [MTKTextureLoader.Option: Any]) {
        entries.append((source, Self.generateMipmaps(options), Self.origin(options), texture))
    }

    private static func generateMipmaps(_ options: [MTKTextureLoader.Option: Any]) -> Bool {
        (options[.generateMipmaps] as? Bool) ?? false
    }

    private static func origin(_ options: [MTKTextureLoader.Option: Any]) -> String {
        (options[.origin] as? MTKTextureLoader.Origin)?.rawValue ?? ""
    }
}

/// The materials one load has made, so meshes whose source materials are equivalent share one.
/// ModelIO makes a material object per submesh and names needn't be unique, so neither identity
/// nor name tells sources apart: two are equivalent when every property ModelIO gives them is
/// equal (names and facing aside), which makes the Satin materials they produce identical.
/// Meshes sharing a material share edits to it; clone it to change one.
final class LoadedMaterials {
    let textures = LoadedTextures()
    private var materials: [(source: MDLMaterial, material: PhysicalMaterial)] = []

    func material(for source: MDLMaterial, context: Context, textureLoader: MTKTextureLoader) -> PhysicalMaterial {
        for entry in materials where Self.areEquivalent(entry.source, source) {
            return entry.material
        }
        let material = PhysicalMaterial(context: context)
        material.setProperties(from: source, textureLoader: textureLoader, textures: textures)
        materials.append((source, material))
        return material
    }

    static func areEquivalent(_ first: MDLMaterial, _ second: MDLMaterial) -> Bool {
        guard first.count == second.count, first.base === second.base else { return false }
        for index in 0 ..< first.count {
            guard let property = first[index], let other = second.propertyNamed(property.name),
                  areEqual(property, other)
            else { return false }
        }
        return true
    }

    /// Equal in semantic, type and value. A texture is its source and its sampler transform (ModelIO
    /// gives every texture one, usually identity); one without a source matches nothing.
    static func areEqual(_ first: MDLMaterialProperty, _ second: MDLMaterialProperty) -> Bool {
        guard first.semantic == second.semantic, first.type == second.type else { return false }
        switch first.type {
        case .none:
            return true
        case .string:
            return first.stringValue == second.stringValue
        case .URL:
            return first.urlValue == second.urlValue
        case .texture:
            guard let source = first.stringValue, source == second.stringValue else { return false }
            return first.textureSamplerValue?.transform?.matrix == second.textureSamplerValue?.transform?.matrix
        case .color:
            guard let firstColor = first.color, let secondColor = second.color else { return first.color == nil && second.color == nil }
            return firstColor.components == secondColor.components && (firstColor.colorSpace?.name as String?) == (secondColor.colorSpace?.name as String?)
        case .float:
            return first.floatValue == second.floatValue
        case .float2:
            return first.float2Value == second.float2Value
        case .float3:
            return first.float3Value == second.float3Value
        case .float4:
            return first.float4Value == second.float4Value
        case .matrix44:
            return first.matrix4x4 == second.matrix4x4
        case .buffer:
            return false
        @unknown default:
            return false
        }
    }
}
