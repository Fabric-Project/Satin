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

    public init(context: Context) {
        self.context = context
        let length = alignedSize * context.maxBuffersInFlight * context.vertexAmplificationCount
        guard let buffer = context.device.makeBuffer(length: length, options: [MTLResourceOptions.cpuCacheModeWriteCombined]) else { fatalError("Couldn't not create Vertex Uniform Buffer") }
        self.buffer = buffer
        self.buffer.label = "Vertex Uniforms"
    }

    public func update(object: Object, camera: Camera, viewport: simd_float4, index: Int) {
        if index == 0 {
            self.index = (self.index + 1) % context.maxBuffersInFlight
            offset = alignedSize * self.index * context.vertexAmplificationCount
        }

        uniforms = UnsafeMutableRawPointer(buffer.contents() + offset).bindMemory(to: VertexUniforms.self, capacity: context.vertexAmplificationCount)

        uniforms[index].modelMatrix = object.worldMatrix
        uniforms[index].viewMatrix = camera.viewMatrix
        uniforms[index].modelViewMatrix = camera.viewMatrix * object.worldMatrix
        uniforms[index].projectionMatrix = camera.projectionMatrix
        uniforms[index].viewProjectionMatrix = camera.viewProjectionMatrix
        uniforms[index].modelViewProjectionMatrix = camera.viewProjectionMatrix * object.worldMatrix
        uniforms[index].inverseModelViewProjectionMatrix = uniforms[index].modelViewProjectionMatrix.inverse
        uniforms[index].inverseViewMatrix = camera.worldMatrix
        uniforms[index].normalMatrix = object.normalMatrix
        uniforms[index].viewport = viewport
        uniforms[index].worldCameraPosition = camera.worldPosition
        uniforms[index].worldCameraViewDirection = camera.viewDirection
    }
}
