//
//  Material.swift
//  Satin
//
//  Created by Reza Ali on 7/24/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Metal
import simd

public struct DepthBias: Codable, Equatable {
    var bias: Float
    var slope: Float
    var clamp: Float

    public init(bias: Float, slope: Float, clamp: Float) {
        self.bias = bias
        self.slope = slope
        self.clamp = clamp
    }
}

open class Material: Codable {
    private static func vertexDescriptorHasAttributes(_ descriptor: MTLVertexDescriptor) -> Bool {
        for attribute in VertexAttributeIndex.allCases {
            if descriptor.attributes[attribute.rawValue].format != .invalid {
                return true
            }
        }
        return false
    }
    
    let id: String = UUID().uuidString

    var prefix: String {
        var result = String(describing: type(of: self)).replacingOccurrences(of: "Material", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != result {
            result = result.replacingOccurrences(of: bundleName, with: "")
        }
        result = result.replacingOccurrences(of: ".", with: "")
        return result
    }

    public lazy var label: String = prefix

    public var vertexDescriptor: MTLVertexDescriptor {
        get { renderingConfiguration.vertexDescriptor }
        set { renderingConfiguration.vertexDescriptor = newValue }
    }

    public var tessellationDescriptor: TessellationDescriptor? {
        get { renderingConfiguration.tessellationDescriptor }
        set { renderingConfiguration.tessellationDescriptor = newValue }
    }

    private var parametersSubscription: AnyCancellable?

    public private(set) var shader: Shader? {
        didSet {
            if shader != oldValue, let shader = shader {
                setupShaderRenderingConfiguration(shader)
                setupShaderParametersSubscription(shader)
            }
        }
    }

    public var sourceRGBBlendFactor: MTLBlendFactor {
        get { renderingConfiguration.blending.sourceRGBBlendFactor }
        set { renderingConfiguration.blending.sourceRGBBlendFactor = newValue }
    }

    public var sourceAlphaBlendFactor: MTLBlendFactor {
        get { renderingConfiguration.blending.sourceAlphaBlendFactor }
        set { renderingConfiguration.blending.sourceAlphaBlendFactor = newValue }
    }

    public var destinationRGBBlendFactor: MTLBlendFactor {
        get { renderingConfiguration.blending.destinationRGBBlendFactor }
        set { renderingConfiguration.blending.destinationRGBBlendFactor = newValue }
    }

    public var destinationAlphaBlendFactor: MTLBlendFactor {
        get { renderingConfiguration.blending.destinationAlphaBlendFactor }
        set { renderingConfiguration.blending.destinationAlphaBlendFactor = newValue }
    }

    public var rgbBlendOperation: MTLBlendOperation {
        get { renderingConfiguration.blending.rgbBlendOperation }
        set { renderingConfiguration.blending.rgbBlendOperation = newValue }
    }

    public var alphaBlendOperation: MTLBlendOperation {
        get { renderingConfiguration.blending.alphaBlendOperation }
        set { renderingConfiguration.blending.alphaBlendOperation = newValue }
    }

    private var renderingConfiguration = RenderingConfiguration() {
        didSet {
            if renderingConfiguration != oldValue, let shader = shader {
                setupShaderRenderingConfiguration(shader)
            }
        }
    }

    public let parametersSetPublisher = PassthroughSubject<ParameterGroup, Never>()
    public private(set) var parameters: ParameterGroup = ParameterGroup() {
        didSet {
            if parameters == oldValue { return }
            parameters.label = "\(label) Uniforms"
            //objectWillChange.send()
            parametersSetPublisher.send(parameters)
        }
    }

    // The uniforms snapshot this lease's draws bind: taken once per lease, parameter group and
    // content revision, so a material shared by many meshes in one record copies its uniforms once,
    // and a change between records gets a new snapshot.
    private var uniformsSnapshotLeaseToken: UInt64 = 0
    private var uniformsSnapshotParameters: ParameterGroup?
    private var uniformsSnapshotRevision: UInt64 = 0
    private var uniformsSnapshot: (buffer: MTLBuffer, offset: Int)?

    /// What a material binds at one buffer index; a draw binds the first that is set, in this order.
    private struct BufferSlot {
        var uniformBuffer: UniformBuffer?
        var structBuffer: BindableBuffer?
        var buffer: MTLBuffer?
    }

    /// The material's own bindings, indexed by the index enums' raw values and grown on demand, so
    /// a draw reads them without hashing.
    private var vertexBufferSlots: [BufferSlot] = []
    private var vertexTextureSlots: [MTLTexture?] = []
    private var fragmentBufferSlots: [BufferSlot] = []
    private var fragmentTextureSlots: [MTLTexture?] = []

    /// Grows `slots` so `index` is valid, filling new entries with `empty`.
    private static func makeRoom<Slot>(in slots: inout [Slot], for index: Int, empty: Slot) {
        if index >= slots.count {
            slots.append(contentsOf: repeatElement(empty, count: index + 1 - slots.count))
        }
    }

    public internal(set) var isClone = false

    /// Sends the material whenever its shader's parameters are replaced after the first time.
    public let updatedPublisher = PassthroughSubject<Material, Never>()

    public let context: Context

    public var instancing: Bool {
        get { renderingConfiguration.instancing }
        set { renderingConfiguration.instancing = newValue }
    }

    public var castShadow: Bool {
        get { renderingConfiguration.castShadow }
        set { renderingConfiguration.castShadow = newValue }
    }

    public var receiveShadow: Bool {
        get { renderingConfiguration.receiveShadow }
        set { renderingConfiguration.receiveShadow = newValue }
    }

    public var lighting: Bool {
        get { renderingConfiguration.lighting }
        set { renderingConfiguration.lighting = newValue }
    }

    public var directShadowCount: Int {
        get { renderingConfiguration.directShadowCount }
        set {
            guard renderingConfiguration.directShadowCount != newValue else { return }
            renderingConfiguration.directShadowCount = newValue
        }
    }

    public var directShadowTextureCount: Int {
        get { renderingConfiguration.directShadowTextureCount }
        set {
            guard renderingConfiguration.directShadowTextureCount != newValue else { return }
            renderingConfiguration.directShadowTextureCount = newValue
        }
    }

    public var projectorCount: Int {
        get { renderingConfiguration.projectorCount }
        set {
            guard renderingConfiguration.projectorCount != newValue else { return }
            renderingConfiguration.projectorCount = newValue
        }
    }

    public var lightCount: Int {
        get { renderingConfiguration.lightCount }
        set {
            guard renderingConfiguration.lightCount != newValue else { return }
            renderingConfiguration.lightCount = newValue
        }
    }

    public var blending: Blending {
        get { renderingConfiguration.blending.type }
        set { renderingConfiguration.blending.type = newValue }
    }

    public var depthClipMode: MTLDepthClipMode = .clip
    public var depthStencilState: MTLDepthStencilState?
    private var alphaOitDepthStencilState: MTLDepthStencilState?
    public var depthCompareFunction: MTLCompareFunction = .greaterEqual {
        didSet {
            if oldValue != depthCompareFunction {
                depthNeedsUpdate = true
                alphaOitDepthStencilState = nil
            }
        }
    }

    public var depthWriteEnabled = true {
        didSet {
            if oldValue != depthWriteEnabled {
                depthNeedsUpdate = true
                alphaOitDepthStencilState = nil
            }
        }
    }

    private var depthNeedsUpdate = false

    public var depthBias: DepthBias?
    public var onUpdate: (() -> Void)?

    // MARK: - Rendering Path

    /// Controls which render pass this material participates in.
    ///
    /// - `.unlit`: Fragment function returns color directly. No G-buffer writes. Material always
    ///   renders in a forward pass after the main surface pass, regardless of `renderer.renderingMode`.
    ///   Fragment function signature is unchanged from the traditional `half4` return.
    /// - `.surface`: Material implements `evaluateSurface()` and includes `SurfaceOutput.metal`.
    ///   Participates in the G-buffer pass under `.forwardPlus` and `.deferredGeometry` modes.
    public enum LightingModel {
        case unlit
        case surface
    }

    /// The lighting model for this material. Override in subclasses to change routing.
    /// Default is `.surface` — override to `.unlit` for fonts, video planes, UI overlays, etc.
    open var lightingModel: LightingModel { .surface }

    /// Declares which G-buffer outputs this material's shader writes.
    ///
    /// The renderer intersects this with `renderer.activeOutputs` per draw call. Outputs not
    /// declared here receive the attachment clear value (zeros) for this material's pixels —
    /// declaring an output the shader doesn't write is a silent no-op, not a compile error.
    /// Surface materials that implement `evaluateSurface()` should override this to declare
    /// all outputs their shader supports.
    open var supportedOutputs: RendererOutputs { [.color] }

    var supportsAlphaOrderIndependentTransparency: Bool { false }

    public required init(context: Context) {
        self.context = context
        parametersSetPublisher.send(parameters)
    }

    public init(shader: Shader) {
        self.context = shader.context
        self.shader = shader
        label = shader.label
        renderingConfiguration = shader.configuration.rendering
        setupShaderParametersSubscription(shader)
        parametersSetPublisher.send(parameters)
    }

    // MARK: - CodingKeys

    public enum CodingKeys: String, CodingKey {
        case label

        case blending
        case sourceRGBBlendFactor
        case sourceAlphaBlendFactor
        case destinationRGBBlendFactor
        case destinationAlphaBlendFactor
        case rgbBlendOperation
        case alphaBlendOperation

        case depthWriteEnabled
        case depthCompareFunction
        case depthBias

        case castShadow
        case receiveShadow

        case parameters
    }

    // MARK: - Decode

    public required init(from decoder: Decoder) throws {
        context = try decoder.requireSatinContext(typeName: String(describing: Self.self))
        try decode(from: decoder)
    }

    public func decode(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        label = try values.decode(String.self, forKey: .label)

        blending = try values.decode(Blending.self, forKey: .blending)
        sourceRGBBlendFactor = try values.decode(MTLBlendFactor.self, forKey: .sourceRGBBlendFactor)
        sourceAlphaBlendFactor = try values.decode(MTLBlendFactor.self, forKey: .sourceAlphaBlendFactor)
        destinationRGBBlendFactor = try values.decode(MTLBlendFactor.self, forKey: .destinationRGBBlendFactor)
        destinationAlphaBlendFactor = try values.decode(MTLBlendFactor.self, forKey: .destinationAlphaBlendFactor)
        rgbBlendOperation = try values.decode(MTLBlendOperation.self, forKey: .rgbBlendOperation)
        alphaBlendOperation = try values.decode(MTLBlendOperation.self, forKey: .alphaBlendOperation)

        depthWriteEnabled = try values.decode(Bool.self, forKey: .depthWriteEnabled)
        depthCompareFunction = try values.decode(MTLCompareFunction.self, forKey: .depthCompareFunction)
        depthBias = try values.decode(DepthBias?.self, forKey: .depthBias)

        castShadow = try values.decode(Bool.self, forKey: .castShadow)
        receiveShadow = try values.decode(Bool.self, forKey: .receiveShadow)

        parameters = try values.decode(ParameterGroup.self, forKey: .parameters)
    }

    // MARK: - Encode

    open func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)

        try container.encode(blending, forKey: .blending)
        try container.encode(sourceRGBBlendFactor, forKey: .sourceRGBBlendFactor)
        try container.encode(sourceAlphaBlendFactor, forKey: .sourceAlphaBlendFactor)
        try container.encode(destinationRGBBlendFactor, forKey: .destinationRGBBlendFactor)
        try container.encode(destinationAlphaBlendFactor, forKey: .destinationAlphaBlendFactor)
        try container.encode(rgbBlendOperation, forKey: .rgbBlendOperation)
        try container.encode(alphaBlendOperation, forKey: .alphaBlendOperation)

        try container.encode(depthWriteEnabled, forKey: .depthWriteEnabled)
        try container.encode(depthCompareFunction, forKey: .depthCompareFunction)
        try container.encode(depthBias, forKey: .depthBias)

        try container.encode(castShadow, forKey: .castShadow)
        try container.encode(receiveShadow, forKey: .receiveShadow)

        try container.encode(parameters, forKey: .parameters)
    }

    open func setup() {
        setupDepthStencilState()
        setupShader()
//        objectWillChange.send()
    }

    private func makeDepthStencilState(depthWriteEnabled: Bool, labelSuffix: String) -> MTLDepthStencilState? {
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.label = "\(label) \(labelSuffix)"
        depthStateDesciptor.depthCompareFunction = depthCompareFunction
        depthStateDesciptor.isDepthWriteEnabled = depthWriteEnabled

        return context.device.makeDepthStencilState(descriptor: depthStateDesciptor)
    }

    func setupDepthStencilState() {
        guard context.depthPixelFormat != .invalid,
              depthNeedsUpdate || depthStencilState == nil || alphaOitDepthStencilState == nil
        else { return }

        depthStencilState = makeDepthStencilState(
            depthWriteEnabled: depthWriteEnabled,
            labelSuffix: "Depth Stencil State"
        )
        alphaOitDepthStencilState = makeDepthStencilState(
            depthWriteEnabled: false,
            labelSuffix: "Alpha OIT Depth Stencil State"
        )

        depthNeedsUpdate = false
    }

    // MARK: - Shader

    open func createShader() -> Shader {
        SourceShader(context: context, label: label, pipelineURL: getPipelinesMaterialsURL(label)!.appendingPathComponent("Shaders.metal"))
    }

    open func setupShader() {
        if shader == nil {
            shader = createShader()
            isClone = false
        } else if let shader = shader, isClone, shader.configuration.rendering != renderingConfiguration {
            self.shader = shader.clone()
            isClone = false
        }

        guard Self.vertexDescriptorHasAttributes(vertexDescriptor) else { return }
        shader?.setup()
    }

    open func setupShaderRenderingConfiguration(_ shader: Shader) {
        shader.renderingConfiguration = renderingConfiguration
        //objectWillChange.send()
    }

    open func setupShaderParametersSubscription(_ shader: Shader) {
        var receivedInitialParameters = false
        // Unowned: the subscription is this object's own, cancelled before it goes, and an unowned
        // capture needs no side table on an object every frame retains.
        parametersSubscription = shader.parametersPublisher.sink { [unowned self] newParameters in

            let isInitialParameters = !receivedInitialParameters
            receivedInitialParameters = true

            self.parameters.setFrom(newParameters)

            self.parameters.label = newParameters.label

            //self.objectWillChange.send()

            self.parametersSetPublisher.send(self.parameters)

            if !isInitialParameters {
                self.updatedPublisher.send(self)
            }
        }
    }

    open func update() {
        updateDepth()
        updateShader()
        onUpdate?()
    }

    open func updateShader() {
        if shader == nil { setupShader() }
        guard Self.vertexDescriptorHasAttributes(vertexDescriptor) else { return }
        shader?.update()
    }

    open func updateDepth() {
        if depthNeedsUpdate { setupDepthStencilState() }
    }

    open func encode(in context: EncodingContext) {}

    // MARK: - Draw

    /// Records what drawing with this material needs for one draw: its pipeline for the pass and
    /// layout, depth state, uniforms, buffers and textures. Subclasses add their own bindings and
    /// call `super`; state the context doesn't model goes through `context.addCustomCommand`.
    open func draw(in context: MaterialDrawContext) {
        let shadow = context.isShadowPass
        // Read once for the whole draw: a class property read is a checked access each time.
        guard let shader else {
            recordDepthState(in: context, shadow: shadow)
            return
        }
        // Resolved first: compiling a pipeline on its first use reflects which resources it reads,
        // a layout variant's included, and the bindings below are made from that.
        let pipeline = shader.getPipeline(renderContext: context.renderContext, shadow: shadow, layout: context.layout)
        recordUniforms(in: context, shader: shader, shadow: shadow)
        recordDepthState(in: context, shadow: shadow)
        recordBuffers(in: context, shader: shader)
        recordTextures(in: context, shader: shader)
        if let pipeline {
            context.setPipeline(pipeline)
        }
    }

    private func recordUniforms(in context: MaterialDrawContext, shader: Shader, shadow: Bool) {
        guard let uniforms = uniformsBinding(in: context) else { return }

        if shader.vertexWantsMaterialUniforms {
            context.setVertexBuffer(uniforms.buffer, offset: uniforms.offset, index: .MaterialUniforms)
        }

        if !shadow, shader.fragmentWantsMaterialUniforms {
            context.setFragmentBuffer(uniforms.buffer, offset: uniforms.offset, index: .MaterialUniforms)
        }
    }

    /// This material's uniforms as they are now, in the draw's arena: the slice its draws bind,
    /// for a subclass that binds them to stages the context doesn't model. Nil when it has none.
    public func uniformsBinding(in context: MaterialDrawContext) -> (buffer: MTLBuffer, offset: Int)? {
        let parameters = self.parameters
        let leaseToken = context.storage.leaseToken
        let revision = parameters.contentRevision
        // Checked before anything else: every draw after the first in a lease is a hit.
        if let uniformsSnapshot,
           uniformsSnapshotLeaseToken == leaseToken,
           uniformsSnapshotParameters === parameters,
           uniformsSnapshotRevision == revision
        {
            return uniformsSnapshot
        }

        let size = parameters.size
        guard size > 0 else { return nil }

        let slice = context.recorder.allocate(length: size)
        slice.contents.copyMemory(from: parameters.data, byteCount: size)
        let snapshot = (buffer: slice.buffer, offset: slice.offset)
        uniformsSnapshot = snapshot
        uniformsSnapshotLeaseToken = leaseToken
        uniformsSnapshotParameters = parameters
        uniformsSnapshotRevision = revision
        return snapshot
    }

    private func recordDepthState(in context: MaterialDrawContext, shadow: Bool) {
        let renderContext = context.renderContext
        guard renderContext.depthPixelFormat != .invalid else { return }
        context.setDepthStencilState(
            (!shadow && renderContext.alphaOitEnabled) ? alphaOitDepthStencilState : depthStencilState,
            bias: depthBias,
            clipMode: depthClipMode
        )
    }

    private func recordBuffers(in context: MaterialDrawContext, shader: Shader) {
        for index in shader.vertexBufferBindingIsUsed {
            let slot = index.rawValue
            guard slot < vertexBufferSlots.count else { continue }
            if let uniformBuffer = vertexBufferSlots[slot].uniformBuffer {
                context.setVertexBuffer(uniformBuffer.buffer, offset: uniformBuffer.offset, index: index)
            } else if let structBuffer = vertexBufferSlots[slot].structBuffer {
                context.setVertexBuffer(structBuffer.buffer, offset: structBuffer.offset, index: index)
            } else if let buffer = vertexBufferSlots[slot].buffer {
                context.setVertexBuffer(buffer, offset: 0, index: index)
            }
        }

        for index in shader.fragmentBufferBindingIsUsed {
            let slot = index.rawValue
            guard slot < fragmentBufferSlots.count else { continue }
            if let uniformBuffer = fragmentBufferSlots[slot].uniformBuffer {
                context.setFragmentBuffer(uniformBuffer.buffer, offset: uniformBuffer.offset, index: index)
            } else if let structBuffer = fragmentBufferSlots[slot].structBuffer {
                context.setFragmentBuffer(structBuffer.buffer, offset: structBuffer.offset, index: index)
            } else if let buffer = fragmentBufferSlots[slot].buffer {
                context.setFragmentBuffer(buffer, offset: 0, index: index)
            }
        }
    }

    private func recordTextures(in context: MaterialDrawContext, shader: Shader) {
        for index in shader.vertexTextureBindingIsUsed {
            let slot = index.rawValue
            if slot < vertexTextureSlots.count, let texture = vertexTextureSlots[slot] {
                context.setVertexTexture(texture, index: index)
            }
        }

        for index in shader.fragmentTextureBindingIsUsed {
            let slot = index.rawValue
            if slot < fragmentTextureSlots.count, let texture = fragmentTextureSlots[slot] {
                context.setFragmentTexture(texture, index: index)
            }
        }
    }

    public func getPipeline(renderContext: Context, shadow: Bool) -> MTLRenderPipelineState? {
        shader?.getPipeline(renderContext: renderContext, shadow: shadow)
    }

    /// The pipeline for drawing a mesh with `layout`, which may differ from this material's own
    /// when the material is shared by meshes with different layouts, skinning or instancing.
    public func getPipeline(renderContext: Context, shadow: Bool, layout: DrawLayout?) -> MTLRenderPipelineState? {
        shader?.getPipeline(renderContext: renderContext, shadow: shadow, layout: layout)
    }

    public func set(_ buffer: MTLBuffer?, index: VertexBufferIndex) {
        Self.makeRoom(in: &vertexBufferSlots, for: index.rawValue, empty: BufferSlot())
        vertexBufferSlots[index.rawValue].buffer = buffer
    }

    public func set(_ uniformBuffer: UniformBuffer?, index: VertexBufferIndex) {
        Self.makeRoom(in: &vertexBufferSlots, for: index.rawValue, empty: BufferSlot())
        vertexBufferSlots[index.rawValue].uniformBuffer = uniformBuffer
    }

    public func set(_ structBuffer: BindableBuffer?, index: VertexBufferIndex) {
        Self.makeRoom(in: &vertexBufferSlots, for: index.rawValue, empty: BufferSlot())
        vertexBufferSlots[index.rawValue].structBuffer = structBuffer
    }

    public func set(_ texture: MTLTexture?, index: VertexTextureIndex) {
        Self.makeRoom(in: &vertexTextureSlots, for: index.rawValue, empty: nil)
        vertexTextureSlots[index.rawValue] = texture
    }

    public func set(_ uniformBuffer: UniformBuffer?, index: FragmentBufferIndex) {
        Self.makeRoom(in: &fragmentBufferSlots, for: index.rawValue, empty: BufferSlot())
        fragmentBufferSlots[index.rawValue].uniformBuffer = uniformBuffer
    }

    public func set(_ structBuffer: BindableBuffer?, index: FragmentBufferIndex) {
        Self.makeRoom(in: &fragmentBufferSlots, for: index.rawValue, empty: BufferSlot())
        fragmentBufferSlots[index.rawValue].structBuffer = structBuffer
    }

    public func set(_ buffer: MTLBuffer?, index: FragmentBufferIndex) {
        Self.makeRoom(in: &fragmentBufferSlots, for: index.rawValue, empty: BufferSlot())
        fragmentBufferSlots[index.rawValue].buffer = buffer
    }

    public func set(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        Self.makeRoom(in: &fragmentTextureSlots, for: index.rawValue, empty: nil)
        fragmentTextureSlots[index.rawValue] = texture
    }

    public func set(_ name: String, _ value: [Float]) {
        let count = value.count
        if count == 1 {
            set(name, value[0])
        } else if count == 2 {
            set(name, simd_make_float2(value[0], value[1]))
        } else if count == 3 {
            set(name, simd_make_float3(value[0], value[1], value[2]))
        } else if count == 4 {
            set(name, simd_make_float4(value[0], value[1], value[2], value[3]))
        }
    }

    public func set(_ name: String, _ value: [Int]) {
        let count = value.count
        if count == 1 {
            set(name, value[0])
        } else if count == 2 {
            set(name, simd_make_int2(Int32(value[0]), Int32(value[1])))
        } else if count == 3 {
            set(name, simd_make_int3(Int32(value[0]), Int32(value[1]), Int32(value[2])))
        } else if count == 4 {
            set(name, simd_make_int4(Int32(value[0]), Int32(value[1]), Int32(value[2]), Int32(value[3])))
        }
    }

    public func set(_ name: String, _ value: Float) {
        if let param = parameters.get(name, as: FloatParameter.self) {
            param.value = value
        } else {
            parameters.append(FloatParameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_float2) {
        if let param = parameters.get(name, as: Float2Parameter.self) {
            param.value = value
        } else {
            parameters.append(Float2Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_float3) {
        if let param = parameters.get(name, as: Float3Parameter.self) {
            param.value = value
        } else {
            parameters.append(Float3Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_float4) {
        if let param = parameters.get(name, as: Float4Parameter.self) {
            param.value = value
        } else {
            parameters.append(Float4Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_float2x2) {
        if let param = parameters.get(name, as: Float2x2Parameter.self) {
            param.value = value
        } else {
            parameters.append(Float2x2Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_float3x3) {
        if let param = parameters.get(name, as: Float3x3Parameter.self) {
            param.value = value
        } else {
            parameters.append(Float3x3Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_float4x4) {
        if let param = parameters.get(name, as: Float4x4Parameter.self) {
            param.value = value
        } else {
            parameters.append(Float4x4Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: Int) {
        if let param = parameters.get(name, as: IntParameter.self) {
            param.value = value
        } else {
            parameters.append(IntParameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_int2) {
        if let param = parameters.get(name, as: Int2Parameter.self) {
            param.value = value
        } else {
            parameters.append(Int2Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_int3) {
        if let param = parameters.get(name, as: Int3Parameter.self) {
            param.value = value
        } else {
            parameters.append(Int3Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: simd_int4) {
        if let param = parameters.get(name, as: Int4Parameter.self) {
            param.value = value
        } else {
            parameters.append(Int4Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: UInt32) {
        if let param = parameters.get(name, as: UInt32Parameter.self) {
            param.value = value
        } else {
            parameters.append(UInt32Parameter(name, value))
        }
    }

    public func set(_ name: String, _ value: Bool) {
        if let param = parameters.get(name) as? BoolParameter {
            param.value = value
        } else {
            parameters.append(BoolParameter(name, value))
        }
    }

    public func setParameters(from incomingParams: ParameterGroup) {
        parameters = incomingParams.clone()
    }

    public func setParameters(from material: Material) {
        parameters = material.parameters.clone()
    }

    public func get(_ name: String) -> (any Parameter)? {
        return parameters.get(name)
    }

    public func get<T>(_ name: String, as: T.Type) -> T? {
        return parameters.get(name, as: T.self)
    }

    deinit {
        shader = nil
    }

    open func clone(context: Context) -> Material {
        let clone: Material = type(of: self).init(context: context)
        clone.isClone = true
        cloneProperties(clone: clone)
        return clone
    }

    open func clone() -> Material {
        clone(context: context)
    }

    public func cloneProperties(clone: Material) {
        clone.label = label
        clone.vertexDescriptor = vertexDescriptor
        clone.instancing = instancing
        clone.lighting = lighting
        clone.lightCount = lightCount

        clone.parameters = parameters.clone()

        clone.onUpdate = onUpdate

        clone.renderingConfiguration = renderingConfiguration

        clone.depthCompareFunction = depthCompareFunction
        clone.depthWriteEnabled = depthWriteEnabled
        clone.depthStencilState = nil
        clone.alphaOitDepthStencilState = nil
        clone.depthNeedsUpdate = true
    }
}

extension Material: Equatable {
    public static func == (lhs: Material, rhs: Material) -> Bool {
        return lhs === rhs
    }
}
