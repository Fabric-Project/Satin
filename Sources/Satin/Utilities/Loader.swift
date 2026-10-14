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
    guard !skeletons.isEmpty || objectAnimation != nil else { return LoadedAsset(root: root, animation: nil) }
    return LoadedAsset(root: root, animation: AssetAnimation(skeletons: skeletons, objectAnimation: objectAnimation, timeRange: assetTimeRange))
}

func loadMesh(mdlMesh: MDLMesh, context: Context, textureLoader: MTKTextureLoader?, instanced: Bool) -> Mesh {
    let geometry = Geometry(context: context)
    let stnMesh = instanced
        ? InstancedMesh(context: context, label: mdlMesh.name, geometry: geometry, material: nil, count: 1)
        : Mesh(context: context, label: mdlMesh.name, geometry: geometry, material: nil)
    stnMesh.cullMode = .none

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
                            let mat = PhysicalMaterial(context: context)
                            mat.setPropertiesFrom(material: mdlMaterial, textureLoader: textureLoader)
                            material = mat
                        }

                        stnMesh.addSubmesh(
                            Submesh(
                                context: context,
                                label: mdlSubmesh.name,
                                parent: stnMesh,
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
                    let mat = PhysicalMaterial(context: context)
                    mat.setPropertiesFrom(material: mdlMaterial, textureLoader: textureLoader)
                    stnMesh.material = mat
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

    return stnMesh
}

func loadAssetChildren(parent: Object, children: [MDLObject], context: Context, textureLoader: MTKTextureLoader?,
                       instanced: Bool, record: inout AssetLoadRecord) {
    for child in children {
        let object: Object
        if let mdlMesh = child as? MDLMesh {
            let mesh = loadMesh(mdlMesh: mdlMesh, context: context, textureLoader: textureLoader, instanced: instanced)
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
