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

public protocol MaterialDelegate: AnyObject {
    func updated(material: Material)
}

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

open class Material: Codable, ObservableObject {
    @Published open var id: String = UUID().uuidString

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

    public var uniforms: UniformBuffer?

    public let parametersSetPublisher = PassthroughSubject<ParameterGroup, Never>()
    private var parameterGroupSubscriptions = Set<AnyCancellable>()
    public private(set) lazy var parameters: ParameterGroup = {
        let params = ParameterGroup("\(label) Uniforms")
        setupParameterGroupSubscriptions(params)
        return params
    }() {
        didSet {
            setupParameterGroupSubscriptions(parameters)
            uniformsNeedsUpdate = true
            objectWillChange.send()
            parametersSetPublisher.send(parameters)
        }
    }

    public private(set) var vertexUniformBuffers: [VertexBufferIndex: UniformBuffer] = [:]
    public private(set) var vertexStructBuffers: [VertexBufferIndex: any BindableBuffer] = [:]
    public private(set) var vertexBuffers: [VertexBufferIndex: MTLBuffer] = [:]
    public private(set) var vertexTextures: [VertexTextureIndex: MTLTexture] = [:]

    public private(set) var fragmentUniformBuffers: [FragmentBufferIndex: UniformBuffer] = [:]
    public private(set) var fragmentStructBuffers: [FragmentBufferIndex: any BindableBuffer] = [:]
    public private(set) var fragmentBuffers: [FragmentBufferIndex: MTLBuffer] = [:]
    public private(set) var fragmentTextures: [FragmentTextureIndex: MTLTexture] = [:]

    public internal(set) var isClone = false
    public weak var delegate: MaterialDelegate?

    public let updatedPublisher = PassthroughSubject<Material, Never>()

    public var context: Context? {
        didSet {
            if let context, context != oldValue {
                setup()
            }
        }
    }

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

    public var shadowCount: Int {
        get { renderingConfiguration.shadowCount }
        set { renderingConfiguration.shadowCount = newValue }
    }

    public var lightCount: Int {
        get { renderingConfiguration.lightCount }
        set { renderingConfiguration.lightCount = newValue }
    }

    public var blending: Blending {
        get { renderingConfiguration.blending.type }
        set { renderingConfiguration.blending.type = newValue }
    }

    public var depthClipMode: MTLDepthClipMode = .clip
    public var depthStencilState: MTLDepthStencilState?
    public var depthCompareFunction: MTLCompareFunction = .greaterEqual {
        didSet {
            if oldValue != depthCompareFunction {
                depthNeedsUpdate = true
            }
        }
    }

    public var depthWriteEnabled = true {
        didSet {
            if oldValue != depthWriteEnabled {
                depthNeedsUpdate = true
            }
        }
    }

    private var uniformsNeedsUpdate = true
    private var depthNeedsUpdate = false

    public var depthBias: DepthBias?
    public var onBind: ((_ renderEncoder: MTLRenderCommandEncoder) -> Void)?
    public var onUpdate: (() -> Void)?

    public required init() {}

    public init(shader: Shader) {
        self.shader = shader
        label = shader.label
        renderingConfiguration = shader.configuration.rendering
        setupShaderParametersSubscription(shader)
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
        setupUniforms()
        objectWillChange.send()
    }

    private func setupParameterGroupSubscriptions(_ parameterGroup: ParameterGroup) {
        parameterGroupSubscriptions.removeAll()

        parameterGroup.parameterAddedPublisher.sink { [weak self] _ in
            guard let self else { return }
            self.uniformsNeedsUpdate = true
            self.objectWillChange.send()
        }.store(in: &parameterGroupSubscriptions)

        parameterGroup.parameterRemovedPublisher.sink { [weak self] _ in
            guard let self else { return }
            self.uniformsNeedsUpdate = true
            self.objectWillChange.send()
        }.store(in: &parameterGroupSubscriptions)

        parameterGroup.parameterUpdatedPublisher.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
        }.store(in: &parameterGroupSubscriptions)

        parameterGroup.loadedPublisher.sink { [weak self] _ in
            guard let self else { return }
            self.uniformsNeedsUpdate = true
            self.objectWillChange.send()
        }.store(in: &parameterGroupSubscriptions)

        parameterGroup.clearedPublisher.sink { [weak self] _ in
            guard let self else { return }
            self.uniformsNeedsUpdate = true
            self.objectWillChange.send()
        }.store(in: &parameterGroupSubscriptions)
    }

    func setupDepthStencilState() {
        guard let context,
              context.depthPixelFormat != .invalid,
              depthNeedsUpdate || depthStencilState == nil
        else { return }

        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.label = "\(label) Depth Stencil State"
        depthStateDesciptor.depthCompareFunction = depthCompareFunction
        depthStateDesciptor.isDepthWriteEnabled = depthWriteEnabled

        depthStencilState = context.device.makeDepthStencilState(descriptor: depthStateDesciptor)

        depthNeedsUpdate = false
    }

    // MARK: - Shader

    open func createShader() -> Shader {
        SourceShader(
            label: label,
            pipelineURL: getPipelinesMaterialsURL(label)!.appendingPathComponent("Shaders.metal")
        )
    }

    open func setupShader() {
        if shader == nil {
            shader = createShader()
            isClone = false
        } else if let shader = shader, isClone, shader.configuration.rendering != renderingConfiguration {
            self.shader = shader.clone()
            isClone = false
        }

        shader?.context = context
        shader?.setup()
    }

    open func setupShaderRenderingConfiguration(_ shader: Shader) {
        shader.renderingConfiguration = renderingConfiguration
        objectWillChange.send()
    }

    open func setupShaderParametersSubscription(_ shader: Shader) {
        parametersSubscription = shader.parametersPublisher.sink { [weak self] newParameters in
            guard let self else { return }

            self.parameters.setFrom(newParameters)

            self.parameters.label = newParameters.label

            self.uniformsNeedsUpdate = true

            self.objectWillChange.send()

            self.parametersSetPublisher.send(self.parameters)

            self.updatedPublisher.send(self)

            self.delegate?.updated(material: self)
        }
    }

    open func setupUniforms() {
        guard let context, parameters.size > 0, uniformsNeedsUpdate else { return }

        uniforms = UniformBuffer(
            device: context.device,
            parameters: parameters,
            maxBuffersInFlight: context.maxBuffersInFlight
        )

        uniformsNeedsUpdate = false
    }

    open func update() {
        updateDepth()
        updateShader()
        updateUniforms()
        onUpdate?()
    }

    open func updateShader() {
        if shader == nil { setupShader() }
        shader?.update()
    }

    open func updateDepth() {
        if depthNeedsUpdate { setupDepthStencilState() }
    }

    open func updateUniforms() {
        if uniformsNeedsUpdate { setupUniforms() }
        uniforms?.update()
    }

    open func encode(_ commandBuffer: MTLCommandBuffer) {}

    open func bindPipeline(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        guard let pipeline = shader?.getPipeline(renderContext: renderContext, shadow: shadow) else { return }
        renderEncoderState.pipeline = pipeline
    }

    open func bindUniforms(renderEncoderState: RenderEncoderState, shadow: Bool) {
        guard let shader else { return }

        if shader.vertexWantsMaterialUniforms {
            renderEncoderState.vertexMaterialUniforms = uniforms
        }

        if !shadow, shader.fragmentWantsMaterialUniforms {
            renderEncoderState.fragmentMaterialUniforms = uniforms
        }
    }

    open func bindDepthStates(renderContext: Context, renderEncoderState: RenderEncoderState) {
        guard renderContext.depthPixelFormat != .invalid else { return }
        renderEncoderState.depthStencilState = depthStencilState
        renderEncoderState.depthBias = depthBias
        renderEncoderState.depthClipMode = depthClipMode
    }

    open func bindBuffers(renderEncoderState: RenderEncoderState) {
        guard let shader else { return }

        for index in shader.vertexBufferBindingIsUsed {
            if let uniformBuffer = vertexUniformBuffers[index] {
                renderEncoderState.setVertexBuffer(
                    uniformBuffer.buffer,
                    offset: uniformBuffer.offset,
                    index: index
                )
            } else if let structBuffer = vertexStructBuffers[index] {
                renderEncoderState.setVertexBuffer(
                    structBuffer.buffer,
                    offset: structBuffer.offset,
                    index: index
                )
            } else if let buffer = vertexBuffers[index] {
                renderEncoderState.setVertexBuffer(
                    buffer,
                    offset: 0,
                    index: index
                )
            }
        }

        for index in shader.fragmentBufferBindingIsUsed {
            if let uniformBuffer = fragmentUniformBuffers[index] {
                renderEncoderState.setFragmentBuffer(
                    uniformBuffer.buffer,
                    offset: uniformBuffer.offset,
                    index: index
                )
            } else if let structBuffer = fragmentStructBuffers[index] {
                renderEncoderState.setFragmentBuffer(
                    structBuffer.buffer,
                    offset: structBuffer.offset,
                    index: index
                )
            } else if let buffer = fragmentBuffers[index] {
                renderEncoderState.setFragmentBuffer(
                    buffer,
                    offset: 0,
                    index: index
                )
            }
        }
    }

    open func bindTextures(renderEncoderState: RenderEncoderState) {
        guard let shader else { return }

        for index in shader.vertexTextureBindingIsUsed {
            if let texture = vertexTextures[index] {
                renderEncoderState.setVertexTexture(texture, index: index)
            }
        }

        for index in shader.fragmentTextureBindingIsUsed {
            if let texture = fragmentTextures[index] {
                renderEncoderState.setFragmentTexture(texture, index: index)
            }
        }
    }

    open func bind(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        bindUniforms(renderEncoderState: renderEncoderState, shadow: shadow)
        bindDepthStates(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState
        )
        bindBuffers(renderEncoderState: renderEncoderState)
        bindTextures(renderEncoderState: renderEncoderState)
        bindPipeline(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )
        onBind?(renderEncoderState.renderEncoder)
    }

    public func getPipeline(renderContext: Context, shadow: Bool) -> MTLRenderPipelineState? {
        shader?.getPipeline(renderContext: renderContext, shadow: shadow)
    }

    public func set(_ buffer: MTLBuffer?, index: VertexBufferIndex) {
        if let buffer = buffer {
            vertexBuffers[index] = buffer
        } else {
            vertexBuffers.removeValue(forKey: index)
        }
    }

    public func set(_ uniformBuffer: UniformBuffer?, index: VertexBufferIndex) {
        if let uniformBuffer {
            vertexUniformBuffers[index] = uniformBuffer
        } else {
            vertexUniformBuffers.removeValue(forKey: index)
        }
    }

    public func set(_ structBuffer: BindableBuffer?, index: VertexBufferIndex) {
        if let structBuffer {
            vertexStructBuffers[index] = structBuffer
        } else {
            vertexStructBuffers.removeValue(forKey: index)
        }
    }

    public func set(_ texture: MTLTexture?, index: VertexTextureIndex) {
        if let texture = texture {
            vertexTextures[index] = texture
        } else {
            vertexTextures.removeValue(forKey: index)
        }
    }

    public func set(_ uniformBuffer: UniformBuffer?, index: FragmentBufferIndex) {
        if let uniformBuffer {
            fragmentUniformBuffers[index] = uniformBuffer
        } else {
            fragmentUniformBuffers.removeValue(forKey: index)
        }
    }

    public func set(_ structBuffer: BindableBuffer?, index: FragmentBufferIndex) {
        if let structBuffer {
            fragmentStructBuffers[index] = structBuffer
        } else {
            fragmentStructBuffers.removeValue(forKey: index)
        }
    }

    public func set(_ buffer: MTLBuffer?, index: FragmentBufferIndex) {
        if let buffer = buffer {
            fragmentBuffers[index] = buffer
        } else {
            fragmentBuffers.removeValue(forKey: index)
        }
    }

    public func set(_ texture: MTLTexture?, index: FragmentTextureIndex) {
        if let texture = texture {
            fragmentTextures[index] = texture
        } else {
            fragmentTextures.removeValue(forKey: index)
        }
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
        delegate = nil
        shader = nil
    }

    open func clone() -> Material {
        let clone: Material = type(of: self).init()
        clone.isClone = true
        cloneProperties(clone: clone)
        return clone
    }

    public func cloneProperties(clone: Material) {
        clone.label = label
        clone.vertexDescriptor = vertexDescriptor
        clone.instancing = instancing
        clone.lighting = lighting
        clone.lightCount = lightCount

        clone.delegate = delegate
        clone.parameters = parameters.clone()

        clone.onUpdate = onUpdate
        clone.onBind = onBind

        clone.renderingConfiguration = renderingConfiguration

        clone.depthStencilState = depthStencilState
        clone.depthCompareFunction = depthCompareFunction
        clone.depthWriteEnabled = depthWriteEnabled
    }
}

extension Material: Equatable {
    public static func == (lhs: Material, rhs: Material) -> Bool {
        return lhs === rhs
    }
}
