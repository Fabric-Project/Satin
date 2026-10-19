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

    private struct TextureBinding {
        let texture: MTLTexture?
    }

    // What each Metal argument slot holds, indexed by slot: nil when this state hasn't set it.
    // Arrays sized to the slots Satin binds (they grow if a higher slot is used), so checking a
    // binding is an array read rather than a hash.
    private var vertexBufferBindings = [BufferBinding?](repeating: nil, count: 31)
    private var fragmentBufferBindings = [BufferBinding?](repeating: nil, count: 31)
    private var vertexTextureBindings = [TextureBinding?](repeating: nil, count: 31)
    /// Fragment textures by slot, whether set by index or as a PBR map: both name the same slots.
    private var fragmentTextureBindings = [TextureBinding?](repeating: nil, count: 31)

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int, index: VertexBufferIndex) {
        let slot = index.rawValue
        if Self.binding(vertexBufferBindings, at: slot).map({ $0.buffer === buffer && $0.offset == offset }) == true { return }
        renderEncoder.setVertexBuffer(buffer, offset: offset, index: slot)
        Self.store(BufferBinding(buffer: buffer, offset: offset), in: &vertexBufferBindings, at: slot)
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int, index: FragmentBufferIndex) {
        let slot = index.rawValue
        if Self.binding(fragmentBufferBindings, at: slot).map({ $0.buffer === buffer && $0.offset == offset }) == true { return }
        renderEncoder.setFragmentBuffer(buffer, offset: offset, index: slot)
        Self.store(BufferBinding(buffer: buffer, offset: offset), in: &fragmentBufferBindings, at: slot)
    }

    /// Forgets the buffers this state believes are bound, after something set them behind its back.
    public func invalidateBufferBindings() {
        for slot in vertexBufferBindings.indices { vertexBufferBindings[slot] = nil }
        for slot in fragmentBufferBindings.indices { fragmentBufferBindings[slot] = nil }
    }

    public func setFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        setFragmentTexture(texture, slot: type.index)
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        let slot = index.rawValue
        if Self.binding(vertexTextureBindings, at: slot).map({ $0.texture === texture }) == true { return }
        renderEncoder.setVertexTexture(texture, index: slot)
        Self.store(TextureBinding(texture: texture), in: &vertexTextureBindings, at: slot)
    }

    public func setFragmentTexture(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        setFragmentTexture(texture, slot: index.rawValue)
    }

    private func setFragmentTexture(_ texture: MTLTexture?, slot: Int) {
        if Self.binding(fragmentTextureBindings, at: slot).map({ $0.texture === texture }) == true { return }
        renderEncoder.setFragmentTexture(texture, index: slot)
        Self.store(TextureBinding(texture: texture), in: &fragmentTextureBindings, at: slot)
    }

    private static func binding<Binding>(_ bindings: [Binding?], at slot: Int) -> Binding? {
        slot < bindings.count ? bindings[slot] : nil
    }

    private static func store<Binding>(_ binding: Binding, in bindings: inout [Binding?], at slot: Int) {
        if slot >= bindings.count {
            bindings.append(contentsOf: repeatElement(nil, count: slot - bindings.count + 1))
        }
        bindings[slot] = binding
    }

    init(renderEncoder: MTLRenderCommandEncoder) {
        self.renderEncoder = renderEncoder
    }
}
