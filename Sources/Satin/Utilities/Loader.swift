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
public func loadAnimatedAsset(url: URL, context: Context, textureLoader: MTKTextureLoader? = nil, instanced: Bool = false) -> LoadedAsset {
    loadAssetHierarchy(url: url, context: context, textureLoader: textureLoader, startPoseOnly: false, instanced: instanced)
}

/// Loads a model as its meshes, each placed by its world transform, posed at the start of its
/// animation. Only that pose is read from the animation.
public func loadAsset(url: URL, context: Context, textureLoader: MTKTextureLoader? = nil) -> Object? {
    Object.flatten(loadAssetHierarchy(url: url, context: context, textureLoader: textureLoader, startPoseOnly: true).root)
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
}

/// The model's hierarchy and animation, posed at its start. `startPoseOnly` reads just that
/// pose, for a model that will not be animated.
func loadAssetHierarchy(url: URL, context: Context, textureLoader: MTKTextureLoader?, startPoseOnly: Bool, instanced: Bool = false) -> LoadedAsset {
    let asset = MDLAsset(url: url)
    if textureLoader != nil { asset.loadTextures() }

    let root = Object(context: context, label: url.deletingPathExtension().lastPathComponent)
    var record = AssetLoadRecord()
    loadAssetChildren(parent: root, children: (0 ..< asset.count).map { asset.object(at: $0) }, context: context,
                      textureLoader: textureLoader, instanced: instanced, record: &record)

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

func loadMesh(mdlMesh: MDLMesh, context: Context, textureLoader: MTKTextureLoader?, instanced: Bool, materials: LoadedMaterials) -> Mesh {
    let geometry = Geometry(context: context)
    let stnMesh = instanced
        ? InstancedMesh(context: context, label: mdlMesh.name, geometry: geometry, material: nil, count: 1)
        : Mesh(context: context, label: mdlMesh.name, geometry: geometry, material: nil)

    // 0.1 appears to fix USD import issues with parts of sponza model...
    mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.1)

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

func loadAssetChildren(parent: Object, children: [MDLObject], context: Context, textureLoader: MTKTextureLoader?,
                       instanced: Bool, record: inout AssetLoadRecord) {
    for child in children {
        let object: Object
        if let mdlMesh = child as? MDLMesh {
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
                          instanced: instanced, record: &record)
    }
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
