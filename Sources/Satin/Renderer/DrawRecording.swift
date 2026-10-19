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

// MARK: - Recorder

/// The commands one draw records, replayed into a render command encoder when the draw executes.
/// Bindings are captured with their offsets when they are recorded, so a later change to an object
/// cannot alter a recorded draw. One recorder is reused per encoder: replaying keeps its storage.
final class DrawRecorder {
    enum Command {
        case vertexBuffer(MTLBuffer, offset: Int, index: VertexBufferIndex)
        case fragmentBuffer(MTLBuffer, offset: Int, index: FragmentBufferIndex)
        case vertexTexture(MTLTexture?, index: VertexTextureIndex)
        case fragmentTexture(MTLTexture?, index: FragmentTextureIndex)
        case fragmentPBRTexture(MTLTexture?, type: PBRTextureType)
        case fragmentSampler(MTLSamplerState, index: FragmentSamplerIndex)
        case pipeline(MTLRenderPipelineState)
        case depthStencil(MTLDepthStencilState?, bias: DepthBias?, clipMode: MTLDepthClipMode?)
        case drawPrimitives(MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
        case drawIndexedPrimitives(MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: MTLBuffer, indexBufferOffset: Int, instanceCount: Int)
        case custom((MTLRenderCommandEncoder) -> Void)
    }

    private(set) var commands: [Command] = []

    func record(_ command: Command) {
        commands.append(command)
    }

    func reset() {
        commands.removeAll(keepingCapacity: true)
    }

    /// Executes the recorded commands in order, through `state` so redundant state changes are skipped.
    func replay(into state: RenderEncoderState) {
        let renderEncoder = state.renderEncoder
        for command in commands {
            switch command {
            case let .vertexBuffer(buffer, offset, index):
                state.setVertexBuffer(buffer, offset: offset, index: index)
            case let .fragmentBuffer(buffer, offset, index):
                state.setFragmentBuffer(buffer, offset: offset, index: index)
            case let .vertexTexture(texture, index):
                state.setVertexTexture(texture, index: index)
            case let .fragmentTexture(texture, index):
                state.setFragmentTexture(texture, index: index)
            case let .fragmentPBRTexture(texture, type):
                state.setFragmentPBRTexture(texture, type: type)
            case let .fragmentSampler(sampler, index):
                renderEncoder.setFragmentSamplerState(sampler, index: index.rawValue)
            case let .pipeline(pipeline):
                state.pipeline = pipeline
            case let .depthStencil(depthStencilState, bias, clipMode):
                state.depthStencilState = depthStencilState
                state.depthBias = bias
                state.depthClipMode = clipMode
            case let .drawPrimitives(type, vertexStart, vertexCount, instanceCount):
                renderEncoder.drawPrimitives(type: type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount)
            case let .drawIndexedPrimitives(type, indexCount, indexType, indexBuffer, indexBufferOffset, instanceCount):
                renderEncoder.drawIndexedPrimitives(
                    type: type,
                    indexCount: indexCount,
                    indexType: indexType,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: indexBufferOffset,
                    instanceCount: instanceCount
                )
            case let .custom(command):
                command(renderEncoder)
                // A custom command may set anything: forget what the encoder is known to hold.
                state.invalidateBufferBindings()
            }
        }
    }
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
    let recorder: DrawRecorder

    public var isShadowPass: Bool { pass == .shadow }

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex) {
        recorder.record(.vertexBuffer(buffer, offset: offset, index: index))
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: FragmentBufferIndex) {
        recorder.record(.fragmentBuffer(buffer, offset: offset, index: index))
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        recorder.record(.vertexTexture(texture, index: index))
    }

    public func setFragmentTexture(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        recorder.record(.fragmentTexture(texture, index: index))
    }

    public func setFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        recorder.record(.fragmentPBRTexture(texture, type: type))
    }

    public func setFragmentSamplerState(_ sampler: MTLSamplerState, index: FragmentSamplerIndex) {
        recorder.record(.fragmentSampler(sampler, index: index))
    }

    /// Runs `command` on the live encoder when this draw executes, after what was recorded before it.
    /// It must capture the values it uses: it runs later, not now.
    public func addCustomCommand(_ command: @escaping (MTLRenderCommandEncoder) -> Void) {
        recorder.record(.custom(command))
    }

    func setPipeline(_ pipeline: MTLRenderPipelineState) {
        recorder.record(.pipeline(pipeline))
    }

    func setDepthStencilState(_ depthStencilState: MTLDepthStencilState?, bias: DepthBias?, clipMode: MTLDepthClipMode?) {
        recorder.record(.depthStencil(depthStencilState, bias: bias, clipMode: clipMode))
    }
}

/// What a geometry's `draw(in:)` records for one draw: its vertex buffers, joint palette and draw call.
public struct GeometryDrawContext {
    public let pass: RenderPass
    /// Instances to draw.
    public let instanceCount: Int
    /// Added to the geometry's own index buffer offset: a submesh's range of a shared index buffer.
    public let indexBufferOffset: Int
    public let vertexStart: Int
    let recorder: DrawRecorder

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex) {
        recorder.record(.vertexBuffer(buffer, offset: offset, index: index))
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        recorder.record(.vertexTexture(texture, index: index))
    }

    public func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        recorder.record(.drawPrimitives(type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount))
    }

    public func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: MTLBuffer, indexBufferOffset: Int, instanceCount: Int) {
        recorder.record(.drawIndexedPrimitives(
            type,
            indexCount: indexCount,
            indexType: indexType,
            indexBuffer: indexBuffer,
            indexBufferOffset: indexBufferOffset,
            instanceCount: instanceCount
        ))
    }

    /// Runs `command` on the live encoder when this draw executes: for draws the context does not
    /// model, such as tessellation patches. It must capture the values it uses.
    public func addCustomCommand(_ command: @escaping (MTLRenderCommandEncoder) -> Void) {
        recorder.record(.custom(command))
    }

    /// Binds `palette` at the joint-matrices index, as it is now.
    func setJointPalette(_ palette: JointPalette) {
        recorder.record(.vertexBuffer(palette.buffer, offset: palette.offset, index: .JointMatrices))
        palette.markDrawn()
    }
}

/// What a renderable's `draw(in:)` records for one draw in one pass: it composes its material's and
/// geometry's draws, and may add bindings and custom commands of its own.
public struct RenderableDrawContext {
    public let renderContext: Context
    public let pass: RenderPass
    let recorder: DrawRecorder

    public var isShadowPass: Bool { pass == .shadow }

    /// The context for drawing `material` with `layout` in this pass.
    public func materialContext(layout: DrawLayout?) -> MaterialDrawContext {
        MaterialDrawContext(renderContext: renderContext, pass: pass, layout: layout, recorder: recorder)
    }

    /// The context for drawing a geometry in this pass.
    public func geometryContext(instanceCount: Int, indexBufferOffset: Int = 0, vertexStart: Int = 0) -> GeometryDrawContext {
        GeometryDrawContext(pass: pass, instanceCount: instanceCount, indexBufferOffset: indexBufferOffset, vertexStart: vertexStart, recorder: recorder)
    }

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: VertexBufferIndex) {
        recorder.record(.vertexBuffer(buffer, offset: offset, index: index))
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int = 0, index: FragmentBufferIndex) {
        recorder.record(.fragmentBuffer(buffer, offset: offset, index: index))
    }

    /// Runs `command` on the live encoder when this draw executes, after what was recorded before it.
    /// It must capture the values it uses.
    public func addCustomCommand(_ command: @escaping (MTLRenderCommandEncoder) -> Void) {
        recorder.record(.custom(command))
    }
}

// MARK: - Encoding

extension Renderable {
    /// Records this renderable's draw for one pass and executes it into `renderEncoderState`.
    func encodeDraw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool, recorder: DrawRecorder) {
        recorder.reset()
        draw(in: RenderableDrawContext(renderContext: renderContext, pass: shadow ? .shadow : .color, recorder: recorder))
        recorder.replay(into: renderEncoderState)
    }
}
