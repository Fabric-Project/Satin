//
//  RenderEncoderState.swift
//
//
//  Created by Reza Ali on 12/12/23.
//

import Foundation
import Metal

public final class RenderEncoderState {
    public let renderEncoder: MTLRenderCommandEncoder

    private struct BufferBinding {
        let buffer: MTLBuffer
        let offset: Int
    }

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
            if let vertexVertexUniforms {
                setVertexBuffer(
                    vertexVertexUniforms.buffer,
                    offset: vertexVertexUniforms.offset,
                    index: .VertexUniforms
                )
            }
        }
    }

    public var fragmentVertexUniforms: VertexUniformBuffer? {
        didSet {
            if let fragmentVertexUniforms {
                setFragmentBuffer(
                    fragmentVertexUniforms.buffer,
                    offset: fragmentVertexUniforms.offset,
                    index: .VertexUniforms
                )
            }
        }
    }

    public var vertexMaterialUniforms: UniformBuffer? {
        didSet {
            if let vertexMaterialUniforms {
                setVertexBuffer(
                    vertexMaterialUniforms.buffer,
                    offset: vertexMaterialUniforms.offset,
                    index: .MaterialUniforms
                )
            }
        }
    }

    public var vertexInstanceUniforms: InstanceMatrixUniformBuffer? {
        didSet {
            if let vertexInstanceUniforms {
                setVertexBuffer(
                    vertexInstanceUniforms.buffer,
                    offset: vertexInstanceUniforms.offset,
                    index: .InstanceMatrixUniforms
                )
            }
        }
    }

    public var fragmentMaterialUniforms: UniformBuffer? {
        didSet {
            if let fragmentMaterialUniforms {
                setFragmentBuffer(
                    fragmentMaterialUniforms.buffer,
                    offset: fragmentMaterialUniforms.offset,
                    index: .MaterialUniforms
                )
            }
        }
    }

    private var vertexBuffers = [VertexBufferIndex: BufferBinding]()
    private var vertexTextures = [VertexTextureIndex: MTLTexture?]()

    private var fragmentBuffers = [FragmentBufferIndex: BufferBinding]()
    private var fragmentPBRTextures = [PBRTextureType: MTLTexture?]()
    private var fragmentTextures = [FragmentTextureIndex: MTLTexture?]()

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int, index: VertexBufferIndex) {
        if let existingBinding = vertexBuffers[index],
           existingBinding.buffer === buffer,
           existingBinding.offset == offset
        {
            return
        }
        else {
            renderEncoder.setVertexBuffer(buffer, offset: offset, index: index.rawValue)
            vertexBuffers[index] = BufferBinding(buffer: buffer, offset: offset)
        }
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int, index: FragmentBufferIndex) {
        if let existingBinding = fragmentBuffers[index],
           existingBinding.buffer === buffer,
           existingBinding.offset == offset
        {
            return
        }
        else {
            renderEncoder.setFragmentBuffer(buffer, offset: offset, index: index.rawValue)
            fragmentBuffers[index] = BufferBinding(buffer: buffer, offset: offset)
        }
    }

    public func invalidateBufferBindings() {
        vertexBuffers.removeAll(keepingCapacity: true)
        fragmentBuffers.removeAll(keepingCapacity: true)
    }

    public func setFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        if let existingTexture = fragmentPBRTextures[type], existingTexture === texture {
            return
        }
        else {
            renderEncoder.setFragmentTexture(texture, index: type.index)
            fragmentPBRTextures[type] = texture
        }
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        if let existingTexture = vertexTextures[index], existingTexture === texture {
            return
        }
        else {
            renderEncoder.setVertexTexture(texture, index: index.rawValue)
            vertexTextures[index] = texture
        }
    }

    public func setFragmentTexture(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        if let existingTexture = fragmentTextures[index], existingTexture === texture {
            return
        }
        else {
            renderEncoder.setFragmentTexture(texture, index: index.rawValue)
            fragmentTextures[index] = texture
        }
    }

    init(renderEncoder: MTLRenderCommandEncoder) {
        self.renderEncoder = renderEncoder
    }
}
