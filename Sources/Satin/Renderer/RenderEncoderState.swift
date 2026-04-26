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

    // Fixed-size arrays replace [Enum: MTLBuffer/MTLTexture] dictionaries.
    // Each index is the enum's rawValue; the outer Optional distinguishes
    // "never bound" (nil) from "bound to this buffer/texture" (.some).
    // For textures the value is MTLTexture?? so nil-textures can be cached too:
    //   nil         = slot never touched
    //   .some(nil)  = slot was explicitly set to nil
    //   .some(t)    = slot was set to t
    //
    // Sizes: VertexBufferIndex max rawValue = 31 (32 slots)
    //        VertexTextureIndex max rawValue = 16 (17 slots)
    //        FragmentBufferIndex max rawValue = 19 (20 slots)
    //        FragmentTextureIndex max rawValue = 39 (40 slots)
    //        PBRTextureType.index max = 23 (24 slots)

    private var vertexBuffers = [MTLBuffer?](repeating: nil, count: 32)
    private var vertexTextureSlots = [MTLTexture??](repeating: nil, count: 17)

    private var fragmentBuffers = [MTLBuffer?](repeating: nil, count: 20)
    private var fragmentPBRTextureSlots = [MTLTexture??](repeating: nil, count: 24)
    private var fragmentTextureSlots = [MTLTexture??](repeating: nil, count: 40)

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int, index: VertexBufferIndex) {
        let i = index.rawValue
        if let existing = vertexBuffers[i], existing === buffer { return }
        vertexBuffers[i] = buffer
        renderEncoder.setVertexBuffer(buffer, offset: offset, index: i)
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int, index: FragmentBufferIndex) {
        let i = index.rawValue
        if let existing = fragmentBuffers[i], existing === buffer { return }
        fragmentBuffers[i] = buffer
        renderEncoder.setFragmentBuffer(buffer, offset: offset, index: i)
    }

    public func setFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        let i = type.index
        if let cached = fragmentPBRTextureSlots[i], cached === texture { return }
        fragmentPBRTextureSlots[i] = .some(texture)
        renderEncoder.setFragmentTexture(texture, index: i)
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        let i = index.rawValue
        if let cached = vertexTextureSlots[i], cached === texture { return }
        vertexTextureSlots[i] = .some(texture)
        renderEncoder.setVertexTexture(texture, index: i)
    }

    public func setFragmentTexture(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        let i = index.rawValue
        if let cached = fragmentTextureSlots[i], cached === texture { return }
        fragmentTextureSlots[i] = .some(texture)
        renderEncoder.setFragmentTexture(texture, index: i)
    }

    init(renderEncoder: MTLRenderCommandEncoder) {
        self.renderEncoder = renderEncoder
    }
}
