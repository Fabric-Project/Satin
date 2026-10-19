//
//  RenderEncoderState.swift
//
//
//  Created by Reza Ali on 12/12/23.
//

import Foundation
import Metal

/// What one render command encoder is known to hold, so a packet sets only what differs.
///
/// A custom command (`addCustomCommand`, `addCustomDraw`) may set anything on the encoder. What it
/// sets holds for the rest of its own packet, its draw included, and bindings recorded after it in
/// that packet are issued again. From the next packet, or Satin's next internal draw (the alpha-OIT
/// resolve), the pass is as Satin set it: each packet sets its own state and bindings, the pass
/// state (viewports, vertex amplification, light, shadow and projector bindings) is put back, and
/// state Satin never sets is reset to the pass default: the whole-target scissor, stencil
/// reference 0, blend colour 0, visibility results off. State that should outlast its packet needs
/// a facility of its own.
///
/// `invalidate()` forgets everything without issuing a call; `beginPacket()` and
/// `beginInternalDraw()` do the putting back, once, after an invalidation.
public final class RenderEncoderState {
    public let renderEncoder: MTLRenderCommandEncoder

    private struct BufferBinding {
        let buffer: MTLBuffer
        let offset: Int
    }

    // MARK: Packet State

    // Each known value is nil when unknown; setting one issues the call when it differs or is
    // unknown. Nil is never sent for these.
    private var knownCullMode: MTLCullMode?
    private var knownWindingOrder: MTLWinding?
    private var knownTriangleFillMode: MTLTriangleFillMode?
    private var knownPipeline: MTLRenderPipelineState?
    private var knownDepthClipMode: MTLDepthClipMode?
    // Nil is a real value for these two (no depth-stencil state, no bias), so each has a flag.
    private var knownDepthStencilState: MTLDepthStencilState?
    private(set) var depthStencilStateIsKnown = false
    private var knownDepthBias: DepthBias?
    private(set) var depthBiasIsKnown = false

    public var cullMode: MTLCullMode? {
        get { knownCullMode }
        set {
            guard let newValue, newValue != knownCullMode else { return }
            renderEncoder.setCullMode(newValue)
            knownCullMode = newValue
        }
    }

    public var windingOrder: MTLWinding? {
        get { knownWindingOrder }
        set {
            guard let newValue, newValue != knownWindingOrder else { return }
            renderEncoder.setFrontFacing(newValue)
            knownWindingOrder = newValue
        }
    }

    public var triangleFillMode: MTLTriangleFillMode? {
        get { knownTriangleFillMode }
        set {
            guard let newValue, newValue != knownTriangleFillMode else { return }
            renderEncoder.setTriangleFillMode(newValue)
            knownTriangleFillMode = newValue
        }
    }

    public var pipeline: MTLRenderPipelineState? {
        get { knownPipeline }
        set {
            guard let newValue, newValue !== knownPipeline else { return }
            renderEncoder.setRenderPipelineState(newValue)
            knownPipeline = newValue
        }
    }

    /// Nil is the encoder's default: no depth test, no depth writes. It is never sent as nil (the
    /// AGX driver crashes on `setDepthStencilState(nil)`), but as that default's state object.
    public var depthStencilState: MTLDepthStencilState? {
        get { knownDepthStencilState }
        set {
            guard !depthStencilStateIsKnown || newValue !== knownDepthStencilState else { return }
            guard let state = newValue ?? defaultDepthStencilState else { return }
            renderEncoder.setDepthStencilState(state)
            knownDepthStencilState = newValue
            depthStencilStateIsKnown = true
        }
    }

    /// The encoder's default depth-stencil state, made the first time a packet asks for none.
    private lazy var defaultDepthStencilState: MTLDepthStencilState? =
        renderEncoder.device.makeDepthStencilState(descriptor: MTLDepthStencilDescriptor())

    public var depthClipMode: MTLDepthClipMode? {
        get { knownDepthClipMode }
        set {
            guard let newValue, newValue != knownDepthClipMode else { return }
            #if !targetEnvironment(simulator)
            renderEncoder.setDepthClipMode(newValue)
            #endif
            knownDepthClipMode = newValue
        }
    }

    public var depthBias: DepthBias? {
        get { knownDepthBias }
        set {
            guard !depthBiasIsKnown || newValue != knownDepthBias else { return }
            if let newValue {
                renderEncoder.setDepthBias(newValue.bias, slopeScale: newValue.slope, clamp: newValue.clamp)
            } else {
                renderEncoder.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
            }
            knownDepthBias = newValue
            depthBiasIsKnown = true
        }
    }

    // MARK: Pass State

    // What the pass set, by slot, put back after a custom command: plain arrays, no hashing.
    private var passFragmentBuffers = [BufferBinding?](repeating: nil, count: 31)
    private var passFragmentTextures = [TextureBinding?](repeating: nil, count: 31)
    private var passViewports: [MTLViewport] = []
    private var passVertexAmplificationCount = 1
    private var passViewMappings: [MTLVertexAmplificationViewMapping] = []
    /// The scissor a pass starts with: the whole target.
    private let passScissorRect: MTLScissorRect
    /// Set by `invalidate()`: the pass state and the unmanaged state are put back at the next
    /// packet or internal draw.
    private(set) var passStateNeedsRestore = false

    /// Sets the pass's viewports.
    public func setPassViewports(_ viewports: [MTLViewport]) {
        passViewports = viewports
        renderEncoder.setViewports(viewports)
    }

    /// Sets the pass's viewport.
    public func setPassViewport(_ viewport: MTLViewport) {
        setPassViewports([viewport])
    }

    /// Sets the pass's vertex amplification.
    public func setPassVertexAmplification(count: Int, viewMappings: [MTLVertexAmplificationViewMapping]) {
        passVertexAmplificationCount = count
        passViewMappings = viewMappings
        var mappings = viewMappings
        renderEncoder.setVertexAmplificationCount(count, viewMappings: &mappings)
    }

    /// Binds a fragment buffer every packet of the pass shares, such as its light data.
    public func setPassFragmentBuffer(_ buffer: MTLBuffer, offset: Int, index: FragmentBufferIndex) {
        Self.store(BufferBinding(buffer: buffer, offset: offset), in: &passFragmentBuffers, at: index.rawValue)
        setFragmentBuffer(buffer, offset: offset, index: index)
    }

    /// Binds fragment textures every packet of the pass shares, such as its shadow maps, from
    /// `range.lowerBound`.
    public func setPassFragmentTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        for (slot, texture) in zip(range, textures) {
            Self.store(TextureBinding(texture: texture), in: &passFragmentTextures, at: slot)
            setFragmentTexture(texture, slot: slot)
        }
    }

    /// Forgets everything the encoder is known to hold, after a custom command may have changed
    /// any of it. Issues no call: the next packet or internal draw sets what it needs.
    public func invalidate() {
        knownCullMode = nil
        knownWindingOrder = nil
        knownTriangleFillMode = nil
        knownPipeline = nil
        knownDepthClipMode = nil
        knownDepthStencilState = nil
        depthStencilStateIsKnown = false
        knownDepthBias = nil
        depthBiasIsKnown = false
        for slot in vertexBufferBindings.indices { vertexBufferBindings[slot] = nil }
        for slot in fragmentBufferBindings.indices { fragmentBufferBindings[slot] = nil }
        for slot in vertexTextureBindings.indices { vertexTextureBindings[slot] = nil }
        for slot in fragmentTextureBindings.indices { fragmentTextureBindings[slot] = nil }
        passStateNeedsRestore = true
    }

    /// Starts a packet: after a custom command, puts the pass back first.
    public func beginPacket() {
        restorePassStateIfNeeded()
    }

    /// Starts a draw Satin issues itself, such as the alpha-OIT resolve: after a custom command,
    /// puts the pass back first.
    public func beginInternalDraw() {
        restorePassStateIfNeeded()
    }

    private func restorePassStateIfNeeded() {
        guard passStateNeedsRestore else { return }
        passStateNeedsRestore = false

        if !passViewports.isEmpty {
            renderEncoder.setViewports(passViewports)
        }
        if passVertexAmplificationCount > 1 {
            var mappings = passViewMappings
            renderEncoder.setVertexAmplificationCount(passVertexAmplificationCount, viewMappings: &mappings)
        }
        for (slot, binding) in passFragmentBuffers.enumerated() {
            if let binding, let index = FragmentBufferIndex(rawValue: slot) {
                setFragmentBuffer(binding.buffer, offset: binding.offset, index: index)
            }
        }
        for (slot, binding) in passFragmentTextures.enumerated() {
            if let binding {
                setFragmentTexture(binding.texture, slot: slot)
            }
        }

        // State Satin never sets, back to the pass default.
        renderEncoder.setScissorRect(passScissorRect)
        renderEncoder.setStencilReferenceValue(0)
        renderEncoder.setBlendColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderEncoder.setVisibilityResultMode(.disabled, offset: 0)
    }

    // MARK: Bindings

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

    /// A state for a pass rendering into a target of `renderTargetSize`.
    init(renderEncoder: MTLRenderCommandEncoder, renderTargetSize: (width: Int, height: Int)) {
        self.renderEncoder = renderEncoder
        passScissorRect = MTLScissorRect(x: 0, y: 0, width: renderTargetSize.width, height: renderTargetSize.height)
    }

    /// A state for a pass encoding with `renderPassDescriptor`: its target is the first attachment
    /// it supplies, or its render target size.
    convenience init(renderEncoder: MTLRenderCommandEncoder, renderPassDescriptor: MTLRenderPassDescriptor) {
        let texture = renderPassDescriptor.colorAttachments[0].texture ?? renderPassDescriptor.depthAttachment.texture
        self.init(
            renderEncoder: renderEncoder,
            renderTargetSize: (
                width: texture?.width ?? renderPassDescriptor.renderTargetWidth,
                height: texture?.height ?? renderPassDescriptor.renderTargetHeight
            )
        )
    }

    /// Whether this state knows the fragment texture at `slot`.
    func hasKnownFragmentTexture(at slot: Int) -> Bool {
        Self.binding(fragmentTextureBindings, at: slot) != nil
    }
}
