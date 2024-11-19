//
//  ComputeProcessor.swift
//  Satin
//
//  Created by Reza Ali on 3/7/24.
//  Copyright © 2023 Reza Ali. All rights reserved.
//

import Combine
import Foundation
import Metal
import simd

public protocol ComputeProcessorDelegate: AnyObject {
    func updated(computeProcessor: ComputeProcessor)
}

open class ComputeProcessor: ComputeShaderDelegate, ObservableObject {
    public internal(set) lazy var label = prefix

    internal var prefix: String {
        var prefix = String(describing: type(of: self)).replacingOccurrences(of: "ComputeProcessor", with: "")
        prefix = prefix.replacingOccurrences(of: "Compute", with: "")
        prefix = prefix.replacingOccurrences(of: "Processor", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != prefix {
            prefix = prefix.replacingOccurrences(of: bundleName, with: "")
        }
        prefix = prefix.replacingOccurrences(of: ".", with: "")
        return prefix
    }

    public weak var delegate: ComputeProcessorDelegate?
    
    public var preCompute: ((_ computeEncoder: MTLComputeCommandEncoder, _ iteration: Int) -> Void)?

    public private(set) var computeUniformBuffers: [ComputeBufferIndex: UniformBuffer] = [:]
    public private(set) var computeStructBuffers: [ComputeBufferIndex: BindableBuffer] = [:]
    public private(set) var computeBuffers: [ComputeBufferIndex: MTLBuffer] = [:]
    public private(set) var computeTextures: [ComputeTextureIndex: MTLTexture] = [:]

    public internal(set) var shader: ComputeShader? {
        didSet {
            if shader != oldValue, let shader = shader {
                reset()
                setupShaderConfiguration(shader)
                setupShaderParametersSubscription(shader)
            }
        }
    }

    public var resetPipeline: MTLComputePipelineState? {
        shader?.resetPipeline
    }

    public var updatePipeline: MTLComputePipelineState? {
        shader?.updatePipeline
    }

    open var defines: [ShaderDefine] {
        get { configuration.defines }
        set { configuration.defines = newValue }
    }

    open var constants: [String] {
        get { configuration.constants }
        set { configuration.constants = newValue }
    }

    public private(set) var uniforms: UniformBuffer?
    private var uniformsNeedsUpdate = true

    public var device: MTLDevice
    public var pipelineURL: URL
    public var live: Bool { didSet { shader?.live = live } }

    public internal(set) var parameters = ParameterGroup()

    private var configuration = ComputeConfiguration() {
        didSet {
            if configuration != oldValue, let shader = shader {
                setupShaderConfiguration(shader)
            }
        }
    }

    internal var _reset = true
    internal var _index = 0
    internal var _count = 0
    internal var _useDispatchThreads = false

    internal var parametersSubscription: AnyCancellable?

    public init(device: MTLDevice, pipelineURL: URL, live: Bool = false) {
        self.device = device
        self.pipelineURL = pipelineURL
        self.live = live

        setup()
    }

    public init(device: MTLDevice, pipelinesURL: URL, live: Bool = false) {
        pipelineURL = pipelinesURL
        self.device = device
        self.live = live

        pipelineURL = pipelineURL.appendingPathComponent(prefix).appendingPathComponent("Shaders.metal")

        setup()
    }

    open func setup() {
        setupFeatures()
        setupShader()
        setupUniforms()
    }

    open func update() {
        updateSize()
        updateShader()
        updateUniforms()
    }

    // MARK: - Features

    private func setupFeatures() {
        _useDispatchThreads = false
        if #available(macOS 10.15, iOS 13, tvOS 13, visionOS 1.0, *) {
            if device.supportsFamily(.common3) || device.supportsFamily(.apple4) || device.supportsFamily(.apple5) || device.supportsFamily(.mac2) || device.supportsFamily(.mac2) {
                _useDispatchThreads = true
            }
        } else {
#if os(macOS)
            if device.supportsFeatureSet(.macOS_GPUFamily1_v1) || device.supportsFeatureSet(.macOS_GPUFamily2_v1) {
                _useDispatchThreads = true
            }
#elseif os(iOS) || os(tvOS) || os(visionOS)
            if device.supportsFeatureSet(.iOS_GPUFamily4_v1) || device.supportsFeatureSet(.iOS_GPUFamily5_v1) {
                _useDispatchThreads = true
            }
#endif
        }
    }

    // MARK: - Shader

    open func createShader() -> ComputeShader {
        let shader = ComputeShader(label: label, pipelineURL: pipelineURL, live: live)
        shader.delegate = self
        return shader
    }

    internal func updated(shader: ComputeShader) {
        print("Updated Shader: \(shader.label)")
        reset()
        delegate?.updated(computeProcessor: self)
    }

    internal func setupShader() {
        if shader == nil { shader = createShader() }
        shader?.device = device
    }

    internal func setupShaderConfiguration(_ shader: ComputeShader) {
        shader.configuration.compute = configuration
    }

    internal func updateShader() {
        if shader == nil { setupShader() }
        shader?.update()
    }

    internal func setupShaderParametersSubscription(_ shader: ComputeShader) {
        parametersSubscription = shader.parametersPublisher.sink { [weak self] parameters in
            self?.updateParameters(parameters)
        }
    }

    // MARK: - Update

    open func update(_ commandBuffer: MTLCommandBuffer, iterations: Int = 1) {
        update()
    }

    open func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        update()
    }

    // MARK: - Reset

    open func reset() {
        _reset = true
        resetIndex()
    }

    open func resetIndex() {
        _index = 0
    }

    // MARK: - Dispatch

    internal func dispatch(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
#if os(macOS) || os(iOS) || os(visionOS)
        if _useDispatchThreads {
            dispatchThreads(computeEncoder: computeEncoder, pipeline: pipeline, iteration: iteration)
        } else {
            dispatchThreadgroups(computeEncoder: computeEncoder, pipeline: pipeline, iteration: iteration)
        }
#elseif os(tvOS)
        _dispatchThreadgroups(computeEncoder: computeEncoder, pipeline: pipeline, iteration: iteration)
#endif
    }

#if os(macOS) || os(iOS) || os(visionOS)
    open func dispatchThreads(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {}
#endif

    open func dispatchThreadgroups(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {}

    // MARK: - Uniforms

    internal func setupUniforms() {
        guard parameters.size > 0 else { return }
        uniforms = UniformBuffer(device: device, parameters: parameters)
        uniformsNeedsUpdate = false
    }

    internal func updateUniforms() {
        if uniformsNeedsUpdate { setupUniforms() }
        uniforms?.update()
    }

    open func bindUniforms(_ computeEncoder: MTLComputeCommandEncoder) {
        guard let uniforms, let shader, shader.resetWantsUniforms || shader.updateWantsUniforms else { return }
        computeEncoder.setBuffer(
            uniforms.buffer,
            offset: uniforms.offset,
            index: ComputeBufferIndex.Uniforms.rawValue
        )
    }

    internal func bindBuffers(_ computeEncoder: MTLComputeCommandEncoder) {
        guard let shader else { return }

        for index in shader.bufferBindingIsUsed {
            if let uniformBuffer = computeUniformBuffers[index] {
                computeEncoder.setBuffer(
                    uniformBuffer.buffer,
                    offset: uniformBuffer.offset,
                    index: index.rawValue
                )
            }
            else if let structBuffer = computeStructBuffers[index] {
                computeEncoder.setBuffer(
                    structBuffer.buffer,
                    offset: structBuffer.offset,
                    index: index.rawValue
                )
            }
            else if let buffer = computeBuffers[index] {
                computeEncoder.setBuffer(
                    buffer,
                    offset: 0,
                    index: index.rawValue
                )
            }
        }
    }

    internal func bindTextures(_ computeEncoder: MTLComputeCommandEncoder) {
        guard let shader else { return }

        for index in shader.textureBindingIsUsed {
            if let texture = computeTextures[index] {
                computeEncoder.setTexture(texture, index: index.rawValue)
            }
        }
    }

    // MARK: - Count / Size

    internal func updateSize() {}

    // MARK: - Buffers

    public func set(_ buffer: MTLBuffer?, index: ComputeBufferIndex) {
        if let buffer {
            computeBuffers[index] = buffer
        } else {
            computeBuffers.removeValue(forKey: index)
        }
    }


    public func set(_ uniformBuffer: UniformBuffer?, index: ComputeBufferIndex) {
        if let uniformBuffer {
            computeUniformBuffers[index] = uniformBuffer
        } else {
            computeUniformBuffers.removeValue(forKey: index)
        }
    }


    public func set(_ structBuffer: BindableBuffer?, index: ComputeBufferIndex) {
        if let structBuffer {
            computeStructBuffers[index] = structBuffer
        } else {
            computeStructBuffers.removeValue(forKey: index)
        }
    }

    // MARK: - Textures

    public func set(_ texture: MTLTexture?, index: ComputeTextureIndex) {
        if let texture = texture {
            computeTextures[index] = texture
        } else {
            computeTextures.removeValue(forKey: index)
        }
    }

    // MARK: - Parameters

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

    internal func updateParameters(_ newParameters: ParameterGroup) {
        parameters.setFrom(newParameters)
        parameters.label = newParameters.label
        uniformsNeedsUpdate = true
        objectWillChange.send()
        delegate?.updated(computeProcessor: self)
    }

    deinit {
        computeUniformBuffers.removeAll()
        computeStructBuffers.removeAll()
        computeBuffers.removeAll()
        computeTextures.removeAll()

        shader = nil
        delegate = nil
    }
}
