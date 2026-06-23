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
    public struct SourceState {
        public let modelMatrix: simd_float4x4
        public let normalMatrix: simd_float3x3

        public init(modelMatrix: simd_float4x4, normalMatrix: simd_float3x3) {
            self.modelMatrix = modelMatrix
            self.normalMatrix = normalMatrix
        }
    }

    public private(set) var context: Context
    public private(set) var maxBuffersInFlight: Int
    public private(set) var encodesPerFrame: Int
    public private(set) var buffer: MTLBuffer
    public private(set) var offset = 0

    private var index: Int = -1
    private var uniforms: UnsafeMutablePointer<VertexUniforms>!
    private let alignedSize = ((MemoryLayout<VertexUniforms>.size + 255) / 256) * 256
    private let totalSlots: Int

    private var previousModelMatrices: [simd_float4x4]
    private var previousViewProjectionMatrices: [simd_float4x4]
    private var repeatedSourceStates: [SourceState] = []
    private var selectedRepeatedSourceState: SourceState?

    public init(
        context: Context,
        maxBuffersInFlight: Int? = nil,
        encodesPerFrame: Int = Satin.maxSubPassesPerFrame
    ) {
        self.context = context
        self.maxBuffersInFlight = max(1, maxBuffersInFlight ?? context.maxBuffersInFlight)
        self.encodesPerFrame = max(1, encodesPerFrame)
        let amplificationCount = max(context.vertexAmplificationCount, 1)
        previousModelMatrices = Array(repeating: matrix_identity_float4x4, count: amplificationCount)
        previousViewProjectionMatrices = Array(repeating: matrix_identity_float4x4, count: amplificationCount)
        totalSlots = self.maxBuffersInFlight * self.encodesPerFrame
        let length = alignedSize * totalSlots * amplificationCount
        guard let buffer = context.device.makeBuffer(length: length, options: [MTLResourceOptions.cpuCacheModeWriteCombined]) else { fatalError("Couldn't not create Vertex Uniform Buffer") }
        self.buffer = buffer
        self.buffer.label = "Vertex Uniforms"
    }

    public func prepareForRepeatedEncoding(count: Int) {
        let count = max(1, count)
        if count > 1 {
            repeatedSourceStates.reserveCapacity(count)
        }
        else {
            repeatedSourceStates.removeAll(keepingCapacity: true)
            selectedRepeatedSourceState = nil
        }
    }

    public func loadRepeatedEncodingSourceStates(_ sourceStates: [SourceState]) {
        repeatedSourceStates = sourceStates
        selectedRepeatedSourceState = nil
    }

    public func captureRepeatedEncodingSourceState(object: Object, iteration: Int, count: Int) {
        let count = max(1, count)
        guard count > 1 else {
            repeatedSourceStates.removeAll(keepingCapacity: true)
            selectedRepeatedSourceState = nil
            return
        }

        let state = SourceState(
            modelMatrix: object.worldMatrix,
            normalMatrix: object.normalMatrix
        )

        if repeatedSourceStates.count != count {
            repeatedSourceStates = Array(repeating: state, count: count)
        }

        let slot = min(max(iteration, 0), count - 1)
        repeatedSourceStates[slot] = state
    }

    public func selectRepeatedEncodingState(iteration: Int, count: Int) {
        let count = max(1, count)
        guard count > 1, repeatedSourceStates.count == count else {
            selectedRepeatedSourceState = nil
            return
        }

        let slot = min(max(iteration, 0), count - 1)
        selectedRepeatedSourceState = repeatedSourceStates[slot]
    }

    public func update(
        object: Object,
        camera: Camera,
        viewport: simd_float4,
        index: Int
    ) {
        if index == 0 {
            self.index = (self.index + 1) % totalSlots
            offset = alignedSize * self.index * context.vertexAmplificationCount
        }

        uniforms = UnsafeMutableRawPointer(buffer.contents() + offset).bindMemory(to: VertexUniforms.self, capacity: context.vertexAmplificationCount)

        let currentModelMatrix = selectedRepeatedSourceState?.modelMatrix ?? object.worldMatrix
        let currentViewProjectionMatrix = camera.viewProjectionMatrix

        uniforms[index].modelMatrix = currentModelMatrix
        uniforms[index].viewMatrix = camera.viewMatrix
        uniforms[index].modelViewMatrix = camera.viewMatrix * currentModelMatrix
        uniforms[index].projectionMatrix = camera.projectionMatrix
        uniforms[index].viewProjectionMatrix = currentViewProjectionMatrix
        uniforms[index].modelViewProjectionMatrix = currentViewProjectionMatrix * currentModelMatrix
        uniforms[index].inverseModelViewProjectionMatrix = uniforms[index].modelViewProjectionMatrix.inverse
        uniforms[index].inverseViewMatrix = camera.worldMatrix
        uniforms[index].normalMatrix = selectedRepeatedSourceState?.normalMatrix ?? object.normalMatrix
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
