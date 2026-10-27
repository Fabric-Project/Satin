//
//  RenderEncoderState.swift
//
//
//  Created by Reza Ali on 12/12/23.
//

import Foundation
import Metal

/// What one render command encoder is known to hold, so a packet sets only what differs. Every
/// call on the encoder goes through it or is recorded packet data, so what it knows is always true.
///
/// One state serves every pass of its owner, one at a time: `begin(renderEncoder:)` starts a pass
/// knowing nothing, and `end()`, right after the encoder's `endEncoding()`, lets go of the encoder
/// and everything bound, keeping only the capacity of its tables. Everything it knows lives in one
/// `KnownState` value, and each setter is one call on it.
public final class RenderEncoderState {
    private var known = KnownState()

    /// The encoder of the pass in progress, between `begin` and `end`.
    public var renderEncoder: MTLRenderCommandEncoder { known.encoder }

    init() {}

    /// Starts a pass on `renderEncoder`, knowing nothing the encoder holds.
    func begin(renderEncoder: MTLRenderCommandEncoder) {
        known.begin(renderEncoder: renderEncoder)
    }

    /// Ends the pass, after its encoder's `endEncoding()`: holds no encoder or binding until the next.
    func end() {
        known.end()
    }

    /// Whether the state holds anything of a pass: its encoder, or any state object or binding.
    var holdsPass: Bool { known.holdsPass }

    // MARK: Packet State

    public var cullMode: MTLCullMode? {
        get { known.cullMode }
        set { known.setCullMode(newValue) }
    }

    public var windingOrder: MTLWinding? {
        get { known.windingOrder }
        set { known.setWindingOrder(newValue) }
    }

    public var triangleFillMode: MTLTriangleFillMode? {
        get { known.triangleFillMode }
        set { known.setTriangleFillMode(newValue) }
    }

    public var pipeline: MTLRenderPipelineState? {
        get { known.pipeline }
        set { known.setPipeline(newValue) }
    }

    /// Nil is the encoder's default: no depth test, no depth writes. It is never sent as nil (the
    /// AGX driver crashes on `setDepthStencilState(nil)`), but as that default's state object.
    public var depthStencilState: MTLDepthStencilState? {
        get { known.depthStencilState }
        set { known.setDepthStencilState(newValue) }
    }

    var depthStencilStateIsKnown: Bool { known.depthStencilStateIsKnown }

    public var depthClipMode: MTLDepthClipMode? {
        get { known.depthClipMode }
        set { known.setDepthClipMode(newValue) }
    }

    public var depthBias: DepthBias? {
        get { known.depthBias }
        set { known.setDepthBias(newValue) }
    }

    var depthBiasIsKnown: Bool { known.depthBiasIsKnown }

    // MARK: Pass State

    /// Sets the pass's viewports.
    public func setPassViewports(_ viewports: [MTLViewport]) {
        known.setPassViewports(viewports)
    }

    /// Sets the pass's viewport.
    public func setPassViewport(_ viewport: MTLViewport) {
        known.setPassViewports(CollectionOfOne(viewport))
    }

    /// Sets the pass's vertex amplification.
    public func setPassVertexAmplification(count: Int, viewMappings: [MTLVertexAmplificationViewMapping]) {
        known.setPassVertexAmplification(count: count, viewMappings: viewMappings)
    }

    /// Binds a fragment buffer every packet of the pass shares, such as its light data.
    public func setPassFragmentBuffer(_ buffer: MTLBuffer, offset: Int, index: FragmentBufferIndex) {
        known.setPassFragmentBuffer(buffer, offset: offset, slot: index.rawValue)
    }

    /// Binds fragment textures every packet of the pass shares, such as its shadow maps, from
    /// `range.lowerBound`.
    public func setPassFragmentTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        known.setPassFragmentTextures(textures, range: range)
    }

    // MARK: Bindings

    public func setVertexBuffer(_ buffer: MTLBuffer, offset: Int, index: VertexBufferIndex) {
        known.setVertexBuffer(buffer, offset: offset, slot: index.rawValue)
    }

    public func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int, index: FragmentBufferIndex) {
        known.setFragmentBuffer(buffer, offset: offset, slot: index.rawValue)
    }

    public func setFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        known.setFragmentTexture(texture, slot: type.index)
    }

    public func setVertexTexture(_ texture: MTLTexture?, index: VertexTextureIndex) {
        known.setVertexTexture(texture, slot: index.rawValue)
    }

    public func setFragmentTexture(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        known.setFragmentTexture(texture, slot: index.rawValue)
    }

    /// Whether this state knows the fragment texture at `slot`.
    func hasKnownFragmentTexture(at slot: Int) -> Bool {
        known.hasKnownFragmentTexture(at: slot)
    }
}

// MARK: - Known State

/// Everything a `RenderEncoderState` knows of its pass, mutated in place: inside its methods every
/// field access is static.
private struct KnownState {
    struct BufferBinding {
        let buffer: MTLBuffer
        let offset: Int
    }

    struct TextureBinding {
        let texture: MTLTexture?
    }

    /// Slots Satin binds; a table grows if a higher slot is used.
    static let slotCount = 31

    private var renderEncoder: MTLRenderCommandEncoder?

    var encoder: MTLRenderCommandEncoder {
        guard let renderEncoder else { preconditionFailure("RenderEncoderState used outside a pass") }
        return renderEncoder
    }

    // Each known value is nil when unknown; setting one issues the call when it differs or is
    // unknown. Nil is never sent for these.
    private(set) var cullMode: MTLCullMode?
    private(set) var windingOrder: MTLWinding?
    private(set) var triangleFillMode: MTLTriangleFillMode?
    private(set) var pipeline: MTLRenderPipelineState?
    private(set) var depthClipMode: MTLDepthClipMode?
    // Nil is a real value for these two (no depth-stencil state, no bias), so each has a flag.
    private(set) var depthStencilState: MTLDepthStencilState?
    private(set) var depthStencilStateIsKnown = false
    private(set) var depthBias: DepthBias?
    private(set) var depthBiasIsKnown = false

    /// The device's default depth-stencil state, made the first time a packet asks for none. It
    /// belongs to the device, not the pass, so it outlives `end()`.
    private var defaultDepthStencilState: MTLDepthStencilState?

    /// The pass's viewports, copied into the state's own array so its capacity is reused.
    private var passViewports: [MTLViewport] = []

    // What each Metal argument slot holds, indexed by slot: nil when this pass hasn't set it.
    private var vertexBufferBindings = ContiguousArray<BufferBinding?>(repeating: nil, count: KnownState.slotCount)
    private var fragmentBufferBindings = ContiguousArray<BufferBinding?>(repeating: nil, count: KnownState.slotCount)
    private var vertexTextureBindings = ContiguousArray<TextureBinding?>(repeating: nil, count: KnownState.slotCount)
    /// Fragment textures by slot, whether set by index or as a PBR map: both name the same slots.
    private var fragmentTextureBindings = ContiguousArray<TextureBinding?>(repeating: nil, count: KnownState.slotCount)

    // MARK: Passes

    mutating func begin(renderEncoder: MTLRenderCommandEncoder) {
        // `end()` already releases and clears the previous pass. Still reset an unfinished
        // state when a caller begins another pass without explicitly ending this state first.
        if self.renderEncoder != nil { forgetPass() }
        self.renderEncoder = renderEncoder
    }

    mutating func end() {
        forgetPass()
    }

    var holdsPass: Bool {
        renderEncoder != nil || pipeline != nil || depthStencilState != nil
            || vertexBufferBindings.contains { $0 != nil } || fragmentBufferBindings.contains { $0 != nil }
            || vertexTextureBindings.contains { $0 != nil } || fragmentTextureBindings.contains { $0 != nil }
    }

    /// Lets go of the encoder and everything the pass set, keeping the tables' capacity.
    private mutating func forgetPass() {
        renderEncoder = nil
        forgetEncoderState()
        passViewports.removeAll(keepingCapacity: true)
    }

    /// Forgets what the encoder holds, without issuing a call: a pass starts knowing nothing.
    private mutating func forgetEncoderState() {
        cullMode = nil
        windingOrder = nil
        triangleFillMode = nil
        pipeline = nil
        depthClipMode = nil
        depthStencilState = nil
        depthStencilStateIsKnown = false
        depthBias = nil
        depthBiasIsKnown = false
        Self.clear(&vertexBufferBindings)
        Self.clear(&fragmentBufferBindings)
        Self.clear(&vertexTextureBindings)
        Self.clear(&fragmentTextureBindings)
    }

    // MARK: Packet State

    mutating func setCullMode(_ newValue: MTLCullMode?) {
        guard let newValue, newValue != cullMode else { return }
        encoder.setCullMode(newValue)
        cullMode = newValue
    }

    mutating func setWindingOrder(_ newValue: MTLWinding?) {
        guard let newValue, newValue != windingOrder else { return }
        encoder.setFrontFacing(newValue)
        windingOrder = newValue
    }

    mutating func setTriangleFillMode(_ newValue: MTLTriangleFillMode?) {
        guard let newValue, newValue != triangleFillMode else { return }
        encoder.setTriangleFillMode(newValue)
        triangleFillMode = newValue
    }

    mutating func setPipeline(_ newValue: MTLRenderPipelineState?) {
        guard let newValue, newValue !== pipeline else { return }
        encoder.setRenderPipelineState(newValue)
        pipeline = newValue
    }

    mutating func setDepthStencilState(_ newValue: MTLDepthStencilState?) {
        guard !depthStencilStateIsKnown || newValue !== depthStencilState else { return }
        let encoder = self.encoder
        if newValue == nil, defaultDepthStencilState == nil {
            defaultDepthStencilState = encoder.device.makeDepthStencilState(descriptor: MTLDepthStencilDescriptor())
        }
        guard let state = newValue ?? defaultDepthStencilState else { return }
        encoder.setDepthStencilState(state)
        depthStencilState = newValue
        depthStencilStateIsKnown = true
    }

    mutating func setDepthClipMode(_ newValue: MTLDepthClipMode?) {
        guard let newValue, newValue != depthClipMode else { return }
        #if !targetEnvironment(simulator)
        encoder.setDepthClipMode(newValue)
        #endif
        depthClipMode = newValue
    }

    mutating func setDepthBias(_ newValue: DepthBias?) {
        guard !depthBiasIsKnown || newValue != depthBias else { return }
        if let newValue {
            encoder.setDepthBias(newValue.bias, slopeScale: newValue.slope, clamp: newValue.clamp)
        } else {
            encoder.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
        }
        depthBias = newValue
        depthBiasIsKnown = true
    }

    // MARK: Pass State

    mutating func setPassViewports<Viewports: Collection>(_ viewports: Viewports) where Viewports.Element == MTLViewport {
        passViewports.removeAll(keepingCapacity: true)
        passViewports.append(contentsOf: viewports)
        encoder.setViewports(passViewports)
    }

    mutating func setPassVertexAmplification(count: Int, viewMappings: [MTLVertexAmplificationViewMapping]) {
        var mappings = viewMappings
        encoder.setVertexAmplificationCount(count, viewMappings: &mappings)
    }

    mutating func setPassFragmentBuffer(_ buffer: MTLBuffer, offset: Int, slot: Int) {
        setFragmentBuffer(buffer, offset: offset, slot: slot)
    }

    mutating func setPassFragmentTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        for (slot, texture) in zip(range, textures) {
            setFragmentTexture(texture, slot: slot)
        }
    }

    // MARK: Bindings

    mutating func setVertexBuffer(_ buffer: MTLBuffer, offset: Int, slot: Int) {
        if let binding = Self.binding(vertexBufferBindings, at: slot), binding.buffer === buffer, binding.offset == offset { return }
        encoder.setVertexBuffer(buffer, offset: offset, index: slot)
        Self.store(BufferBinding(buffer: buffer, offset: offset), in: &vertexBufferBindings, at: slot)
    }

    mutating func setFragmentBuffer(_ buffer: MTLBuffer, offset: Int, slot: Int) {
        if let binding = Self.binding(fragmentBufferBindings, at: slot), binding.buffer === buffer, binding.offset == offset { return }
        encoder.setFragmentBuffer(buffer, offset: offset, index: slot)
        Self.store(BufferBinding(buffer: buffer, offset: offset), in: &fragmentBufferBindings, at: slot)
    }

    mutating func setVertexTexture(_ texture: MTLTexture?, slot: Int) {
        if let binding = Self.binding(vertexTextureBindings, at: slot), binding.texture === texture { return }
        encoder.setVertexTexture(texture, index: slot)
        Self.store(TextureBinding(texture: texture), in: &vertexTextureBindings, at: slot)
    }

    mutating func setFragmentTexture(_ texture: MTLTexture?, slot: Int) {
        if let binding = Self.binding(fragmentTextureBindings, at: slot), binding.texture === texture { return }
        encoder.setFragmentTexture(texture, index: slot)
        Self.store(TextureBinding(texture: texture), in: &fragmentTextureBindings, at: slot)
    }

    func hasKnownFragmentTexture(at slot: Int) -> Bool {
        Self.binding(fragmentTextureBindings, at: slot) != nil
    }

    private static func binding<Binding>(_ bindings: ContiguousArray<Binding?>, at slot: Int) -> Binding? {
        slot < bindings.count ? bindings[slot] : nil
    }

    private static func store<Binding>(_ binding: Binding, in bindings: inout ContiguousArray<Binding?>, at slot: Int) {
        if slot >= bindings.count {
            bindings.append(contentsOf: repeatElement(nil, count: slot - bindings.count + 1))
        }
        bindings[slot] = binding
    }

    private static func clear<Binding>(_ bindings: inout ContiguousArray<Binding?>) {
        for slot in bindings.indices { bindings[slot] = nil }
    }
}
