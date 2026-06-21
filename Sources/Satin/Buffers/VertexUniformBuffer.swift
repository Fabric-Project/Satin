//
//  VertexUniformBuffer.swift
//  Satin
//
//  Created by Reza Ali on 4/21/22.
//

import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class VertexUniformBuffer {
    public private(set) var context: Context
    public private(set) var buffer: MTLBuffer
    public private(set) var offset = 0

    private var index: Int = -1
    private var uniforms: UnsafeMutablePointer<VertexUniforms>!
    private let alignedSize = ((MemoryLayout<VertexUniforms>.size + 255) / 256) * 256
    private let totalSlots: Int

    private var previousModelMatrices: [simd_float4x4]
    private var previousViewProjectionMatrices: [simd_float4x4]

    /// Total slots = maxBuffersInFlight × max(maxSubPassesPerFrame, iterationsPerFrame).
    /// `context.iterationsPerFrame > 1` expands capacity for iterator subgraph use; the shadow
    /// pass budget (maxSubPassesPerFrame) is used when it is larger.
    public init(context: Context) {
        self.context = context
        let amplificationCount = max(context.vertexAmplificationCount, 1)
        previousModelMatrices = Array(repeating: matrix_identity_float4x4, count: amplificationCount)
        previousViewProjectionMatrices = Array(repeating: matrix_identity_float4x4, count: amplificationCount)
        totalSlots = context.maxBuffersInFlight * max(Satin.maxSubPassesPerFrame, context.iterationsPerFrame)
        let length = alignedSize * totalSlots * amplificationCount
        guard let buffer = context.device.makeBuffer(length: length, options: [MTLResourceOptions.cpuCacheModeWriteCombined]) else { fatalError("Couldn't not create Vertex Uniform Buffer") }
        self.buffer = buffer
        self.buffer.label = "Vertex Uniforms"
    }

    public func update(object: Object, camera: Camera, viewport: simd_float4, index: Int) {
        if index == 0 {
            self.index = (self.index + 1) % totalSlots
            offset = alignedSize * self.index * context.vertexAmplificationCount
        }

        uniforms = UnsafeMutableRawPointer(buffer.contents() + offset).bindMemory(to: VertexUniforms.self, capacity: context.vertexAmplificationCount)

        let currentModelMatrix = object.worldMatrix
        let currentViewProjectionMatrix = camera.viewProjectionMatrix

        uniforms[index].modelMatrix = currentModelMatrix
        uniforms[index].viewMatrix = camera.viewMatrix
        uniforms[index].modelViewMatrix = camera.viewMatrix * currentModelMatrix
        uniforms[index].projectionMatrix = camera.projectionMatrix
        uniforms[index].viewProjectionMatrix = currentViewProjectionMatrix
        uniforms[index].modelViewProjectionMatrix = currentViewProjectionMatrix * currentModelMatrix
        uniforms[index].inverseModelViewProjectionMatrix = uniforms[index].modelViewProjectionMatrix.inverse
        uniforms[index].inverseViewMatrix = camera.worldMatrix
        uniforms[index].normalMatrix = object.normalMatrix
        uniforms[index].viewport = viewport
        uniforms[index].worldCameraPosition = camera.worldPosition
        uniforms[index].worldCameraViewDirection = camera.viewDirection
        let previousModelMatrix = previousModelMatrices[index]
        let previousViewProjectionMatrix = previousViewProjectionMatrices[index]
        uniforms[index].previousModelMatrix = previousModelMatrix
        uniforms[index].previousViewProjectionMatrix = previousViewProjectionMatrix
        uniforms[index].previousModelViewProjectionMatrix = previousViewProjectionMatrix * previousModelMatrix

        previousModelMatrices[index] = currentModelMatrix
        previousViewProjectionMatrices[index] = currentViewProjectionMatrix
    }
}
