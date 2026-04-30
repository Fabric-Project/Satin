//
//  RenderEncoderState.swift
//
//
//  Created by Reza Ali on 12/12/23.
//

import Foundation
import Metal

public final class RenderEncoderState {
    private struct BufferBinding {
        let buffer: MTLBuffer
        let offset: Int
    }

    private static let vertexBufferSlotCount = VertexBufferIndex.Custom11.rawValue + 1
    private static let vertexTextureSlotCount = VertexTextureIndex.Custom16.rawValue + 1
    private static let fragmentBufferSlotCount = FragmentBufferIndex.DirectShadowMatrices.rawValue + 1
    private static let fragmentTextureSlotCount = FragmentTextureIndex.DirectShadow0.rawValue + 1
    private static let fragmentPBRTextureSlotCount = PBRTextureType.brdf.index + 1

    public let renderEncoder: MTLRenderCommandEncoder

    public var cullMode: MTLCullMode? {
        didSet {
            if oldValue != cullMode, let cullMode {
                renderEncoder.setCullMode(cullMode)
            }
        }
    }

    public var windingOrder: MTLWinding? {
        didSet {
            if oldValue != windingOrder, let windingOrder {
                renderEncoder.setFrontFacing(windingOrder)
            }
        }
    }

    public var triangleFillMode: MTLTriangleFillMode? {
        didSet {
            if oldValue != triangleFillMode, let triangleFillMode {
                renderEncoder.setTriangleFillMode(triangleFillMode)
            }
        }
    }

    public var pipeline: MTLRenderPipelineState? {
        didSet {
            if oldValue !== pipeline, let pipeline {
                renderEncoder.setRenderPipelineState(pipeline)
            }
        }
    }

    public var depthStencilState: MTLDepthStencilState? {
        didSet {
            if oldValue !== depthStencilState {
                renderEncoder.setDepthStencilState(depthStencilState)
            }
        }
    }

    public var depthClipMode: MTLDepthClipMode? {
        didSet {
            if oldValue != depthClipMode, let depthClipMode {
                #if !targetEnvironment(simulator)
                renderEncoder.setDepthClipMode(depthClipMode)
                #endif
            }
        }
    }

    public var depthBias: DepthBias? {
        didSet {
            if oldValue != depthBias {
                if let depthBias = depthBias {
                    renderEncoder.setDepthBias(depthBias.bias, slopeScale: depthBias.slope, clamp: depthBias.clamp)
                }
                else {
                    renderEncoder.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
                }
            }
        }
    }

    public var vertexVertexUniforms: VertexUniformBuffer? {
        didSet {
            if oldValue !== vertexVertexUniforms, let vertexVertexUniforms {
                renderEncoder.setVertexBuffer(
                    vertexVertexUniforms.buffer,
                    offset: vertexVertexUniforms.offset,
                    index: VertexBufferIndex.VertexUniforms.rawValue
                )
            }
        }
    }

    public var fragmentVertexUniforms: VertexUniformBuffer? {
        didSet {
            if oldValue !== fragmentVertexUniforms, let fragmentVertexUniforms {
                renderEncoder.setFragmentBuffer(
                    fragmentVertexUniforms.buffer,
                    offset: fragmentVertexUniforms.offset,
                    index: FragmentBufferIndex.VertexUniforms.rawValue
                )
            }
        }
    }

    public var vertexMaterialUniforms: UniformBuffer? {
        didSet {
            if oldValue !== vertexMaterialUniforms, let vertexMaterialUniforms {
                renderEncoder.setVertexBuffer(
                    vertexMaterialUniforms.buffer,
                    offset: vertexMaterialUniforms.offset,
                    index: VertexBufferIndex.MaterialUniforms.rawValue
                )
            }
        }
    }

    public var vertexInstanceUniforms: InstanceMatrixUniformBuffer? {
        didSet {
            if oldValue !== vertexInstanceUniforms, let vertexInstanceUniforms {
                renderEncoder.setVertexBuffer(
                    vertexInstanceUniforms.buffer,
                    offset: vertexInstanceUniforms.offset,
                    index: VertexBufferIndex.InstanceMatrixUniforms.rawValue
                )
            }
        }
    }

    public var fragmentMaterialUniforms: UniformBuffer? {
        didSet {
            if oldValue !== fragmentMaterialUniforms, let fragmentMaterialUniforms {
                renderEncoder.setFragmentBuffer(
                    fragmentMaterialUniforms.buffer,
                    offset: fragmentMaterialUniforms.offset,
                    index: FragmentBufferIndex.MaterialUniforms.rawValue
                )
            }
        }
    }

    private var vertexBuffers = [BufferBinding?](repeating: nil, count: RenderEncoderState.vertexBufferSlotCount)
    private var vertexTextures = [MTLTexture??](repeating: nil, count: RenderEncoderState.vertexTextureSlotCount)

    private var fragmentBuffers = [BufferBinding?](repeating: nil, count: RenderEncoderState.fragmentBufferSlotCount)
    private var fragmentPBRTextures = [MTLTexture??](repeating: nil, count: RenderEncoderState.fragmentPBRTextureSlotCount)
    private var fragmentTextures = [MTLTexture??](repeating: nil, count: RenderEncoderState.fragmentTextureSlotCount)

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int, index: VertexBufferIndex) {
        let slot = index.rawValue
        if let existingBinding = vertexBuffers[slot],
           existingBinding.buffer === buffer,
           existingBinding.offset == offset
        {
            return
        }

        renderEncoder.setVertexBuffer(buffer, offset: offset, index: slot)
        vertexBuffers[slot] = BufferBinding(buffer: buffer, offset: offset)
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int, index: FragmentBufferIndex) {
        let slot = index.rawValue
        if let existingBinding = fragmentBuffers[slot],
           existingBinding.buffer === buffer,
           existingBinding.offset == offset
        {
            return
        }

        renderEncoder.setFragmentBuffer(buffer, offset: offset, index: slot)
        fragmentBuffers[slot] = BufferBinding(buffer: buffer, offset: offset)
    }

    public func setFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        let slot = type.index
        if let existingTexture = fragmentPBRTextures[slot], existingTexture === texture {
            return
        }

        renderEncoder.setFragmentTexture(texture, index: slot)
        fragmentPBRTextures[slot] = .some(texture)
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        let slot = index.rawValue
        if let existingTexture = vertexTextures[slot], existingTexture === texture {
            return
        }

        renderEncoder.setVertexTexture(texture, index: slot)
        vertexTextures[slot] = .some(texture)
    }

    public func setFragmentTexture(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        let slot = index.rawValue
        if let existingTexture = fragmentTextures[slot], existingTexture === texture {
            return
        }

        renderEncoder.setFragmentTexture(texture, index: slot)
        fragmentTextures[slot] = .some(texture)
    }

    init(renderEncoder: MTLRenderCommandEncoder) {
        self.renderEncoder = renderEncoder
    }
}
