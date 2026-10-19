//
//  ARLidarMesh.swift
//  Example
//
//  Created by Reza Ali on 4/10/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Metal

public func ARLidarMeshVertexDescriptor() -> MTLVertexDescriptor {
    // position
    let vertexDescriptor = MTLVertexDescriptor()

    vertexDescriptor.attributes[0].format = MTLVertexFormat.float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0

    vertexDescriptor.layouts[0].stride = MemoryLayout<MTLPackedFloat3>.stride
    vertexDescriptor.layouts[0].stepRate = 1
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    return vertexDescriptor
}

public class ARLidarMesh: Renderable {

    override public var opaque: Bool { material?.blending == .disabled }


    public var indexBuffer: MTLBuffer? {
        meshAnchor?.geometry.faces.buffer ?? nil
    }

    public var indexCount: Int {
        (meshAnchor?.geometry.faces.count ?? 0) * 3
    }

    public var vertexBuffer: MTLBuffer? {
        meshAnchor?.geometry.vertices.buffer ?? nil
    }

    public var vertexCount: Int {
        meshAnchor?.geometry.vertices.count ?? 0
    }

    public var normalBuffer: MTLBuffer? {
        meshAnchor?.geometry.normals.buffer ?? nil
    }

    public var normalCount: Int {
        meshAnchor?.geometry.normals.count ?? 0
    }

    public var meshAnchor: ARMeshAnchor?

    public init(context: Context, meshAnchor: ARMeshAnchor, material: Material) {
        self.meshAnchor = meshAnchor
        super.init(context: context, label: "Lidar Mesh \(meshAnchor.identifier)")
        material.vertexDescriptor = ARLidarMeshVertexDescriptor()
        self.material = material
    }

    override public func setup() {
        setupMaterial()
    }

    func setupMaterial() {}

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    // MARK: - Update

    override public func encode(_ commandBuffer: MTLCommandBuffer) {
        material?.encode(commandBuffer)
        super.encode(commandBuffer)
    }

    override public func update() {
        if let meshAnchor = meshAnchor { localMatrix = meshAnchor.transform }
        super.update()
    }

    // MARK: - Draw

    override public func draw(in context: RenderableDrawContext) {
        guard let vertexBuffer = vertexBuffer,
              let indexBuffer = indexBuffer,
              let material = material
        else { return }

        context.setVertexBuffer(context.vertexUniforms.buffer, offset: context.vertexUniforms.offset, index: .VertexUniforms)
        context.setVertexBuffer(vertexBuffer, offset: 0, index: .Vertices)
        material.draw(in: context.materialContext(layout: nil))

        context.geometryContext(instanceCount: 1).drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: 1
        )
    }
}

#endif
