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
    let storage: PacketStorage

    public var isShadowPass: Bool { pass == .shadow }

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex) {
        storage.appendVertexBuffer(buffer, offset: offset, slot: index)
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: FragmentBufferIndex) {
        storage.appendFragmentBuffer(buffer, offset: offset, slot: index)
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

    /// Runs `command` on the live encoder when this draw executes, after what was recorded before it.
    /// It must capture the values it uses: it runs later, not now.
    public func addCustomCommand(_ command: @escaping (MTLRenderCommandEncoder) -> Void) {
        storage.appendCustomCommand(command)
    }

    func setPipeline(_ pipeline: MTLRenderPipelineState) {
        storage.setPipeline(pipeline)
    }

    func setDepthStencilState(_ depthStencilState: MTLDepthStencilState?, bias: DepthBias?, clipMode: MTLDepthClipMode?) {
        storage.setDepthStencilState(depthStencilState, bias: bias, clipMode: clipMode)
    }
}

/// What a geometry's `draw(in:)` records for one draw: its vertex buffers, joint palette and draw
/// call. The draw call finishes the draw.
public struct GeometryDrawContext {
    public let pass: RenderPass
    /// Instances to draw.
    public let instanceCount: Int
    /// Added to the geometry's own index buffer offset: a submesh's range of a shared index buffer.
    public let indexBufferOffset: Int
    public let vertexStart: Int
    let storage: PacketStorage

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex) {
        storage.appendVertexBuffer(buffer, offset: offset, slot: index)
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

    /// Runs `command` on the live encoder when this draw executes, to set state the context does not
    /// model. It must capture the values it uses.
    public func addCustomCommand(_ command: @escaping (MTLRenderCommandEncoder) -> Void) {
        storage.appendCustomCommand(command)
    }

    /// Finishes the draw with `draw`, a command that issues the draw call itself, such as
    /// tessellation patches. It must capture the values it uses.
    public func addCustomDraw(_ draw: @escaping (MTLRenderCommandEncoder) -> Void) {
        storage.appendCustomCommand(draw)
        storage.finishPacket(drawCall: .custom)
    }

    /// Binds `palette` at the joint-matrices index, as it is now.
    func setJointPalette(_ palette: JointPalette) {
        storage.appendVertexBuffer(palette.buffer, offset: palette.offset, slot: .JointMatrices)
        palette.markDrawn()
    }
}

/// What a renderable's `draw(in:)` records for one render event: it composes its material's and
/// geometry's draws, and may add bindings and custom commands of its own. Everything recorded before
/// its first material is shared by every draw it makes in this event.
public struct RenderableDrawContext {
    public let renderContext: Context
    public let pass: RenderPass
    /// Which of the renderable's materials draw in this pass.
    let materialPass: Renderable.MaterialPass
    /// This render event's vertex uniforms: one per view.
    public let vertexUniforms: VertexUniformsBinding
    let storage: PacketStorage

    public var isShadowPass: Bool { pass == .shadow }

    /// The context for drawing a material with `layout` in this pass. Starts a draw: it has no
    /// pipeline until the material sets one.
    public func materialContext(layout: DrawLayout?) -> MaterialDrawContext {
        storage.beginMaterial()
        return MaterialDrawContext(renderContext: renderContext, pass: pass, layout: layout, storage: storage)
    }

    /// The context for drawing a geometry in this pass.
    public func geometryContext(instanceCount: Int, indexBufferOffset: Int = 0, vertexStart: Int = 0) -> GeometryDrawContext {
        GeometryDrawContext(pass: pass, instanceCount: instanceCount, indexBufferOffset: indexBufferOffset, vertexStart: vertexStart, storage: storage)
    }

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex) {
        storage.appendVertexBuffer(buffer, offset: offset, slot: index)
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: FragmentBufferIndex) {
        storage.appendFragmentBuffer(buffer, offset: offset, slot: index)
    }

    /// Runs `command` on the live encoder when this draw executes, after what was recorded before it.
    /// It must capture the values it uses.
    public func addCustomCommand(_ command: @escaping (MTLRenderCommandEncoder) -> Void) {
        storage.appendCustomCommand(command)
    }

    /// Finishes the draw with `draw`, a command that issues the draw call itself, such as a
    /// mesh-shader dispatch. It must capture the values it uses.
    public func addCustomDraw(_ draw: @escaping (MTLRenderCommandEncoder) -> Void) {
        storage.appendCustomCommand(draw)
        storage.finishPacket(drawCall: .custom)
    }
}
