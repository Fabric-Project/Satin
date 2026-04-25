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

    override  public func isDrawable(renderContext: Context, shadow: Bool) -> Bool {
        guard let material,
              material.getPipeline(renderContext: renderContext, shadow: shadow) != nil,
              vertexUniforms[renderContext] != nil,
              vertexBuffer != nil,
              indexBuffer != nil
        else { return false }
        return true
    }


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

    public init(meshAnchor: ARMeshAnchor, material: Material) {
        self.meshAnchor = meshAnchor
        super.init(label: "Lidar Mesh \(meshAnchor.identifier)")
        material.vertexDescriptor = ARLidarMeshVertexDescriptor()
        self.material = material
    }

    override public func setup() {
        setupUniforms()
        setupMaterial()
    }

    func setupMaterial() {
        guard let context, let material else { return }
        material.context = context
    }

    func setupUniforms() {
        guard let context, vertexUniforms[context] == nil else { return }
        vertexUniforms[context] = VertexUniformBuffer(context: context)
    }

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    // MARK: - Update

    override public func encode(_ commandBuffer: MTLCommandBuffer) {
        material?.encode(commandBuffer)
        super.encode(commandBuffer)
    }

    override public func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int) {
        if let meshAnchor = meshAnchor { localMatrix = meshAnchor.transform }
        vertexUniforms[renderContext]?.update(object: self, camera: camera, viewport: viewport, index: index)
        super.update(
            renderContext: renderContext,
            camera: camera,
            viewport: viewport,
            index: index
        )
    }

    // MARK: - Draw

    override public func draw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        guard let vertexUniforms = vertexUniforms[renderContext],
              let vertexBuffer = vertexBuffer,
              let material = material
        else { return }

        renderEncoderState.vertexVertexUniforms = vertexUniforms
        renderEncoderState.setVertexBuffer(vertexBuffer, offset: 0, index: .Vertices)
        material.bind(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )

        let renderEncoder = renderEncoderState.renderEncoder

        if let indexBuffer = indexBuffer {
            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0,
                instanceCount: 1
            )
        } else {
            renderEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: vertexCount,
                instanceCount: 1
            )
        }
    }
}

#endif
