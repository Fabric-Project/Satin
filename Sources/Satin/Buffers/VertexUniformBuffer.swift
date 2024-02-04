//
//  VertexUniformBuffer.swift
//  Satin
//
//  Created by Reza Ali on 4/21/22.
//

import Metal
import simd

public final class VertexUniformBuffer {
    public private(set) var context: Context
    public private(set) var buffer: MTLBuffer
    public private(set) var offset = 0
    public var index: Int { offsetIndex }

    private var offsetIndex: Int = -1
    private var uniforms: UnsafeMutablePointer<VertexUniforms>
    private let alignedSize = ((MemoryLayout<VertexUniforms>.size + 255) / 256) * 256

    public init(context: Context) {
        self.context = context
        let length = alignedSize * Satin.maxBuffersInFlight * context.vertexAmplificationCount
        guard let buffer = context.device.makeBuffer(length: length, options: [MTLResourceOptions.cpuCacheModeWriteCombined]) else { fatalError("Couldn't not create Vertex Uniform Buffer") }
        self.buffer = buffer
        self.buffer.label = "Vertex Uniforms"
        uniforms = UnsafeMutableRawPointer(buffer.contents()).bindMemory(to: VertexUniforms.self, capacity: context.vertexAmplificationCount)
    }

    public func update(object: Object, camera: Camera, viewport: simd_float4, index: Int) {
        offsetIndex = (offsetIndex + 1) % maxBuffersInFlight
        offset = alignedSize * (offsetIndex * context.vertexAmplificationCount) + alignedSize * index

        uniforms = UnsafeMutableRawPointer(buffer.contents() + offset).bindMemory(to: VertexUniforms.self, capacity: 1)

        uniforms[0].modelMatrix = object.worldMatrix
        uniforms[0].viewMatrix = camera.viewMatrix
        uniforms[0].modelViewMatrix = simd_mul(uniforms[0].viewMatrix, uniforms[0].modelMatrix)
        uniforms[0].projectionMatrix = camera.projectionMatrix
        uniforms[0].viewProjectionMatrix = camera.viewProjectionMatrix
        uniforms[0].modelViewProjectionMatrix = simd_mul(camera.viewProjectionMatrix, uniforms[0].modelMatrix)
        uniforms[0].inverseModelViewProjectionMatrix = simd_inverse(uniforms[0].modelViewProjectionMatrix)
        uniforms[0].inverseViewMatrix = camera.worldMatrix
        uniforms[0].normalMatrix = object.normalMatrix
        uniforms[0].viewport = viewport
        uniforms[0].worldCameraPosition = camera.worldPosition
        uniforms[0].worldCameraViewDirection = camera.viewDirection
    }
}
