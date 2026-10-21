//
//  DrawRecording.swift
//  Satin
//

import Metal

/// The kind of pass a draw is recorded for.
public enum RenderPass: Equatable {
    /// A shadow map, drawn from a light.
    case shadow
    /// Any colour-producing pass: forward, deferred geometry, transparent or unlit.
    case color
}

// MARK: - Contexts

/// What a material's `draw(in:)` records for one draw: its pipeline, depth state, uniforms, buffers,
/// textures and samplers. Recorded values are captured, so later changes to the material don't
/// affect this draw.
public struct MaterialDrawContext {
    public let renderContext: Context
    public let pass: RenderPass
    /// What the mesh being drawn needs from the pipeline (see `DrawLayout`); nil uses the material's own.
    public let layout: DrawLayout?
    let recorder: PacketRecorder
    var storage: PacketStorage { recorder.storage }

    public var isShadowPass: Bool { pass == .shadow }

    /// Set `copyOnRecordLength` for CPU-readable data that will change before this draw completes:
    /// that many bytes from `offset` are copied into the frame. The default retains without copying.
    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex, copyOnRecordLength: Int? = nil) {
        let binding = recorder.bufferBinding(buffer, offset: offset, copyOnRecordLength: copyOnRecordLength)
        storage.appendVertexBuffer(binding.buffer, offset: binding.offset, slot: index)
    }

    /// Set `copyOnRecordLength` for CPU-readable data that will change before this draw completes:
    /// that many bytes from `offset` are copied into the frame. The default retains without copying.
    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: FragmentBufferIndex, copyOnRecordLength: Int? = nil) {
        let binding = recorder.bufferBinding(buffer, offset: offset, copyOnRecordLength: copyOnRecordLength)
        storage.appendFragmentBuffer(binding.buffer, offset: binding.offset, slot: index)
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        storage.appendVertexTexture(texture, slot: index)
    }

    public func setFragmentTexture(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        storage.appendFragmentTexture(texture, slot: index)
    }

    public func setFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        storage.appendFragmentPBRTexture(texture, type: type)
    }

    public func setFragmentSamplerState(_ sampler: MTLSamplerState, index: FragmentSamplerIndex) {
        storage.appendFragmentSampler(sampler, slot: index)
    }

    /// Binds `buffer` for a mesh-shader pipeline's object stage.
    public func setObjectBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: ObjectBufferIndex) {
        storage.appendObjectBuffer(buffer, offset: offset, slot: index)
    }

    /// Binds `buffer` for a mesh-shader pipeline's mesh stage.
    public func setMeshBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: MeshBufferIndex) {
        storage.appendMeshBuffer(buffer, offset: offset, slot: index)
    }

    /// Binds the tessellation factors a patch draw reads.
    public func setTessellationFactorBuffer(_ buffer: MTLBuffer, offset: Int = 0, instanceStride: Int = 0) {
        storage.appendTessellationFactorBuffer(buffer, offset: offset, instanceStride: instanceStride)
    }

    func setPipeline(_ pipeline: MTLRenderPipelineState, usage: PipelineResourceUsage? = nil) {
        storage.setPipeline(pipeline, usage: usage)
    }

    func setDepthStencilState(_ depthStencilState: MTLDepthStencilState?, bias: DepthBias?, clipMode: MTLDepthClipMode?) {
        storage.setDepthStencilState(depthStencilState, bias: bias, clipMode: clipMode)
    }
}

/// What a geometry's `draw(in:)` records for one draw: its vertex buffers, joint palette and draw
/// call, after its material's bindings. The draw call finishes the draw.
public struct GeometryDrawContext {
    public let pass: RenderPass
    /// Instances to draw.
    public let instanceCount: Int
    /// Added to the index buffer offset: a submesh's range of its index buffer.
    public let indexBufferOffset: Int
    public let vertexStart: Int
    /// A submesh's indices, drawn over this geometry's vertices instead of its own indices; nil
    /// draws the geometry's own.
    public let elements: Geometry?
    /// A palette replacing the geometry's own, from a posed view of it; nil uses its own.
    public let jointPalette: JointPalette?
    let recorder: PacketRecorder

    /// This context with `jointPalette` replacing the geometry's palette.
    func replacingJointPalette(_ jointPalette: JointPalette?) -> GeometryDrawContext {
        GeometryDrawContext(pass: pass, instanceCount: instanceCount, indexBufferOffset: indexBufferOffset, vertexStart: vertexStart,
                            elements: elements, jointPalette: jointPalette, recorder: recorder)
    }
    var storage: PacketStorage { recorder.storage }

    /// Set `copyOnRecordLength` for CPU-readable data that will change before this draw completes:
    /// that many bytes from `offset` are copied into the frame. The default retains without copying.
    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex, copyOnRecordLength: Int? = nil) {
        let binding = recorder.bufferBinding(buffer, offset: offset, copyOnRecordLength: copyOnRecordLength)
        storage.appendVertexBuffer(binding.buffer, offset: binding.offset, slot: index)
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        storage.appendVertexTexture(texture, slot: index)
    }

    public func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        storage.finishPacket(drawCall: .primitives(type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount))
    }

    public func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: MTLBuffer, indexBufferOffset: Int, instanceCount: Int) {
        let indexBufferIndex = storage.appendIndexBuffer(indexBuffer)
        storage.finishPacket(drawCall: .indexedPrimitives(
            type,
            indexCount: indexCount,
            indexType: indexType,
            indexBufferIndex: indexBufferIndex,
            indexBufferOffset: indexBufferOffset,
            instanceCount: instanceCount
        ))
    }

    /// Binds `buffer` for a mesh-shader pipeline's object stage.
    public func setObjectBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: ObjectBufferIndex) {
        storage.appendObjectBuffer(buffer, offset: offset, slot: index)
    }

    /// Binds `buffer` for a mesh-shader pipeline's mesh stage.
    public func setMeshBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: MeshBufferIndex) {
        storage.appendMeshBuffer(buffer, offset: offset, slot: index)
    }

    /// Binds the tessellation factors a patch draw reads.
    public func setTessellationFactorBuffer(_ buffer: MTLBuffer, offset: Int = 0, instanceStride: Int = 0) {
        storage.appendTessellationFactorBuffer(buffer, offset: offset, instanceStride: instanceStride)
    }

    /// Finishes the draw with `patchCount` tessellation patches of `controlPointCount` control points.
    public func drawPatches(controlPointCount: Int, patchCount: Int, instanceCount: Int) {
        storage.finishPacket(drawCall: .patches(controlPointCount: controlPointCount, patchCount: patchCount, instanceCount: instanceCount))
    }

    /// Finishes the draw with indexed tessellation patches, their control points indexed by
    /// `controlPointIndexBuffer`.
    public func drawIndexedPatches(controlPointCount: Int, patchCount: Int, controlPointIndexBuffer: MTLBuffer, instanceCount: Int) {
        let indexBufferIndex = storage.appendIndexBuffer(controlPointIndexBuffer)
        storage.finishPacket(drawCall: .indexedPatches(controlPointCount: controlPointCount, patchCount: patchCount,
                                                       controlPointIndexBufferIndex: indexBufferIndex, instanceCount: instanceCount))
    }

    /// Finishes the draw with a mesh-shader dispatch of `threadgroups`.
    public func drawMeshThreadgroups(_ threadgroups: MTLSize, threadsPerObjectThreadgroup: MTLSize, threadsPerMeshThreadgroup: MTLSize) {
        storage.finishPacket(drawCall: .meshThreadgroups(threadgroups, threadsPerObjectThreadgroup: threadsPerObjectThreadgroup,
                                                         threadsPerMeshThreadgroup: threadsPerMeshThreadgroup))
    }

    /// Binds `palette`'s snapshot for this record at the joint-matrices index.
    func setJointPalette(_ palette: JointPalette) {
        let snapshot = palette.snapshot(recorder: recorder)
        storage.appendVertexBuffer(snapshot.buffer, offset: snapshot.offset, slot: .JointMatrices)
    }
}

/// What a renderable's `draw(in:)` records for one render event: it composes its material's and
/// geometry's draws, and may add bindings of its own. Everything recorded before
/// its first material is shared by every draw it makes in this event.
public struct RenderableDrawContext {
    public let renderContext: Context
    public let pass: RenderPass
    /// Which of the renderable's materials draw in this pass.
    let materialPass: Renderable.MaterialPass
    /// This render event's vertex uniforms: one per view. Bind them (vertex, fragment, object or
    /// mesh stage); their bytes are written when the submission encodes, so don't read or copy them
    /// while recording.
    public let vertexUniforms: VertexUniformsBinding
    let recorder: PacketRecorder
    var storage: PacketStorage { recorder.storage }

    public var isShadowPass: Bool { pass == .shadow }

    /// The context for drawing a material with `layout` in this pass. Starts a draw: it has no
    /// pipeline until the material sets one.
    public func materialContext(layout: DrawLayout?) -> MaterialDrawContext {
        storage.beginMaterial()
        return MaterialDrawContext(renderContext: renderContext, pass: pass, layout: layout, recorder: recorder)
    }

    /// The context for drawing a geometry in this pass: over `elements`' indices when given, as a
    /// submesh draws its mesh's vertices.
    public func geometryContext(instanceCount: Int, indexBufferOffset: Int = 0, vertexStart: Int = 0, elements: Geometry? = nil) -> GeometryDrawContext {
        GeometryDrawContext(pass: pass, instanceCount: instanceCount, indexBufferOffset: indexBufferOffset, vertexStart: vertexStart,
                            elements: elements, jointPalette: nil, recorder: recorder)
    }

    /// Set `copyOnRecordLength` for CPU-readable data that will change before this draw completes:
    /// that many bytes from `offset` are copied into the frame. The default retains without copying.
    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex, copyOnRecordLength: Int? = nil) {
        let binding = recorder.bufferBinding(buffer, offset: offset, copyOnRecordLength: copyOnRecordLength)
        storage.appendVertexBuffer(binding.buffer, offset: binding.offset, slot: index)
    }

    /// Set `copyOnRecordLength` for CPU-readable data that will change before this draw completes:
    /// that many bytes from `offset` are copied into the frame. The default retains without copying.
    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: FragmentBufferIndex, copyOnRecordLength: Int? = nil) {
        let binding = recorder.bufferBinding(buffer, offset: offset, copyOnRecordLength: copyOnRecordLength)
        storage.appendFragmentBuffer(binding.buffer, offset: binding.offset, slot: index)
    }

    /// Binds `buffer` for a mesh-shader pipeline's object stage.
    public func setObjectBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: ObjectBufferIndex) {
        storage.appendObjectBuffer(buffer, offset: offset, slot: index)
    }

    /// Binds `buffer` for a mesh-shader pipeline's mesh stage.
    public func setMeshBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: MeshBufferIndex) {
        storage.appendMeshBuffer(buffer, offset: offset, slot: index)
    }

    /// Binds the tessellation factors a patch draw reads.
    public func setTessellationFactorBuffer(_ buffer: MTLBuffer, offset: Int = 0, instanceStride: Int = 0) {
        storage.appendTessellationFactorBuffer(buffer, offset: offset, instanceStride: instanceStride)
    }

    /// Finishes the draw with a mesh-shader dispatch of `threadgroups`.
    public func drawMeshThreadgroups(_ threadgroups: MTLSize, threadsPerObjectThreadgroup: MTLSize, threadsPerMeshThreadgroup: MTLSize) {
        storage.finishPacket(drawCall: .meshThreadgroups(threadgroups, threadsPerObjectThreadgroup: threadsPerObjectThreadgroup,
                                                         threadsPerMeshThreadgroup: threadsPerMeshThreadgroup))
    }
}
