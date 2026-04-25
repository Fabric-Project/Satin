//
//  ComputeShader.swift
//
//
//  Created by Reza Ali on 1/8/24.
//

import Combine
import Foundation
import Metal

protocol ComputeShaderDelegate: AnyObject {
    func updated(shader: ComputeShader)
}

open class ComputeShader {
    // MARK: - Reset Pipeline

    public internal(set) var resetPipeline: MTLComputePipelineState?
    public internal(set) var resetPipelineError: Error?
    public internal(set) var resetPipelineReflection: MTLComputePipelineReflection? {
        didSet {
            guard let resetPipelineReflection else { return }

            for binding in resetPipelineReflection.bindings {
                if binding.type == .buffer {
                    if binding.index == ComputeBufferIndex.Uniforms.rawValue {
                        resetWantsUniforms = binding.isUsed
                    } else if let bindingIndex = ComputeBufferIndex(rawValue: binding.index) {
                        bufferBindingIsUsed.insert(bindingIndex)
                    }
                } else if binding.type == .texture, let bindingIndex = ComputeTextureIndex(rawValue: binding.index) {
                    textureBindingIsUsed.insert(bindingIndex)
                }
            }
        }
    }

    // MARK: - Update Pipeline

    public internal(set) var updatePipeline: MTLComputePipelineState?
    public internal(set) var updatePipelineError: Error?
    public internal(set) var updatePipelineReflection: MTLComputePipelineReflection? {
        didSet {
            guard let updatePipelineReflection else { return }

            for binding in updatePipelineReflection.bindings {
                if binding.type == .buffer {
                    if binding.index == ComputeBufferIndex.Uniforms.rawValue {
                        updateWantsUniforms = binding.isUsed
                    } else if let bindingIndex = ComputeBufferIndex(rawValue: binding.index) {
                        bufferBindingIsUsed.insert(bindingIndex)
                    }
                } else if binding.type == .texture, let bindingIndex = ComputeTextureIndex(rawValue: binding.index) {
                    textureBindingIsUsed.insert(bindingIndex)
                }
            }
        }
    }

    public internal(set) var bufferBindingIsUsed: Set<ComputeBufferIndex> = []
    public internal(set) var textureBindingIsUsed: Set<ComputeTextureIndex> = []
    public internal(set) var resetWantsUniforms: Bool = false
    public internal(set) var updateWantsUniforms: Bool = false

    // MARK: - Blending

    public var configuration: ComputeShaderConfiguration {
        didSet {
            if configuration != oldValue {
                definesNeedsUpdate = true
                constantsNeedsUpdate = true

                resetPipelineNeedsUpdate = true
                updatePipelineNeedsUpdate = true

                parametersNeedsUpdate = true
                buffersNeedsUpdate = true
            }
        }
    }

    var libraryURL: URL? {
        get { configuration.libraryURL }
        set { configuration.libraryURL = newValue }
    }

    public var pipelineURL: URL? {
        get { configuration.pipelineURL }
        set { configuration.pipelineURL = newValue }
    }

    open var constants: [String] {
        get { configuration.compute.constants }
        set { configuration.compute.constants = newValue }
    }

    open var defines: [ShaderDefine] {
        get { configuration.compute.defines }
        set { configuration.compute.defines = newValue }
    }

    public var resetFunctionName: String {
        get { configuration.resetFunctionName }
        set { configuration.resetFunctionName = newValue }
    }

    public var updateFunctionName: String {
        get { configuration.updateFunctionName }
        set { configuration.updateFunctionName = newValue }
    }

    public var threadGroupSizeIsMultipleOfThreadExecutionWidth: Bool {
        get { configuration.compute.threadGroupSizeIsMultipleOfThreadExecutionWidth }
        set { configuration.compute.threadGroupSizeIsMultipleOfThreadExecutionWidth = newValue }
    }

    public var device: MTLDevice? {
        didSet {
            if device != nil, device !== oldValue {
                setup()
            }
        }
    }

    public var label: String {
        get { configuration.label }
        set { configuration.label = newValue }
    }

    public var definesNeedsUpdate = false
    public var constantsNeedsUpdate = false

    public var resetPipelineNeedsUpdate = true
    public var updatePipelineNeedsUpdate = true

    public var parametersNeedsUpdate = true
    public var buffersNeedsUpdate = true

    public let parametersPublisher = PassthroughSubject<ParameterGroup, Never>()
    public let buffersPublisher = PassthroughSubject<[ParameterGroup], Never>()

    public private(set) var parameters = ParameterGroup() {
        didSet { parametersPublisher.send(parameters) }
    }

    public private(set) var buffers = [ParameterGroup]() {
        didSet { buffersPublisher.send(buffers) }
    }

    public var source: String? {
        do {
            return try ComputeShaderLibrarySourceCache.getLibrarySource(configuration: configuration.getLibraryConfiguration())
        } catch {
            print("\(label) Compute Shader Source: \(error.localizedDescription)")
        }
        return nil
    }

    public var live: Bool = false {
        didSet {
            compiler.watch = live
        }
    }

    var compilerSubscription: AnyCancellable?
    private lazy var compiler = MetalFileCompiler(watch: live) {
        didSet {
            compilerSubscription = compiler.onUpdatePublisher.sink { [weak self] _ in
                guard let self = self, let pipelineURL = self.pipelineURL else { return }

                ShaderSourceCache.removeSource(url: pipelineURL)

                ComputeShaderLibrarySourceCache.invalidateLibrarySource(
                    configuration: self.configuration.getLibraryConfiguration()
                )

                ComputeShaderLibraryCache.invalidateLibrary(
                    configuration: self.configuration.getLibraryConfiguration()
                )

                ComputeShaderPipelineCache.invalidate(configuration: self.configuration)

                // invalidate caches to recompile shader

                self.resetPipelineNeedsUpdate = true
                self.updatePipelineNeedsUpdate = true
                self.parametersNeedsUpdate = true
                self.buffersNeedsUpdate = true

                print("Updating Compute Shader: \(self.label) at: \(pipelineURL.path)\n")

                self.update()

                self.delegate?.updated(shader: self)
            }
        }
    }

    weak var delegate: ComputeShaderDelegate?

    public required init(configuration: ComputeShaderConfiguration) {
        self.configuration = configuration
        setupShaderCompiler()
    }

    public init(
        label: String,
        resetFunctionName: String? = nil,
        updateFunctionName: String? = nil,
        libraryURL: URL? = nil,
        pipelineURL: URL? = nil,
        live: Bool = false
    ) {
        self.live = live
        configuration = ComputeShaderConfiguration(
            label: label,
            resetFunctionName: resetFunctionName ?? label.camelCase + "Reset",
            updateFunctionName: updateFunctionName ?? label.camelCase + "Update",
            libraryURL: libraryURL,
            pipelineURL: pipelineURL
        )
        setupShaderCompiler()
    }

    func setup() {
        configuration.device = device

        setupDefines()
        setupConstants()

        setupPipelines()

        setupParameters()
        setupBuffers()
    }

    func update() {
        updateDefines()
        updateConstants()

        updatePipelines()
        updateResetPipeline()
        updateUpdatePipeline()

        updateParameters()
        updateBuffers()
    }

    // MARK: - Defines

    open func getDefines() -> [ShaderDefine] {
        return []
    }

    func setupDefines() {
        defines = getDefines()
        definesNeedsUpdate = false
    }

    func updateDefines() {
        if definesNeedsUpdate { setupDefines() }
    }

    // MARK: - Constants

    open func getConstants() -> [String] {
        []
    }

    func setupConstants() {
        constants = getConstants()
        constantsNeedsUpdate = false
    }

    func updateConstants() {
        if constantsNeedsUpdate { setupConstants() }
    }

    // MARK: - Setup Pipelines

    func setupPipelines() {
        setupResetPipeline()
        setupUpdatePipeline()
    }

    // MARK: - Update Pipelines

    func updatePipelines() {
        if resetPipelineNeedsUpdate || updatePipelineNeedsUpdate {
            bufferBindingIsUsed.removeAll()
            textureBindingIsUsed.removeAll()
        }

        updateResetPipeline()
        updateUpdatePipeline()
    }

    // MARK: - Reset Pipeline

    open func makeResetPipeline() throws -> (MTLComputePipelineState?, MTLComputePipelineReflection?) {
        try ComputeShaderPipelineCache.getResetPipeline(configuration: configuration)
    }

    func setupResetPipeline() {
        do {
            let (pipeline, reflection) = try makeResetPipeline()
            resetPipeline = pipeline
            resetPipelineReflection = reflection
            resetPipelineError = nil
        } catch {
            print("\(label) Reset Compute Shader Pipeline: \(error.localizedDescription)")
            if let url = configuration.pipelineURL {
                print("\(label) Compute Shader Path: \(url.path)")
            }
            resetPipelineError = error
            resetPipeline = nil
        }

        resetPipelineNeedsUpdate = false
    }

    func updateResetPipeline() {
        if resetPipelineNeedsUpdate { setupResetPipeline() }
    }

    // MARK: - Update Pipeline

    open func makeUpdatePipeline() throws -> (MTLComputePipelineState?, MTLComputePipelineReflection?) {
        try ComputeShaderPipelineCache.getUpdatePipeline(configuration: configuration)
    }

    func setupUpdatePipeline() {
        do {
            let (pipeline, reflection) = try makeUpdatePipeline()
            updatePipeline = pipeline
            updatePipelineReflection = reflection
            updatePipelineError = nil
        } catch {
            print("\(label) Update Compute Shader Pipeline: \(error.localizedDescription)")
            if let url = configuration.pipelineURL {
                print("\(label) Compute Shader Path: \(url.path)")
            }
            updatePipelineError = error
            updatePipeline = nil
        }

        updatePipelineNeedsUpdate = false
    }

    func updateUpdatePipeline() {
        if updatePipelineNeedsUpdate { setupUpdatePipeline() }
    }

    // MARK: - Parameters

    func setupParameters() {
        do {
            if let pipelineParameters = try ComputeShaderPipelineCache.getPipelineParameters(configuration: configuration) {
                parameters = pipelineParameters
            }
        } catch {
            print("\(label) Compute Shader Parameters: \(error.localizedDescription)")
            if let url = configuration.pipelineURL {
                print("\(label) Compute Shader Path: \(url.path)")
            }
        }

        parametersNeedsUpdate = false
    }

    func updateParameters() {
        if parametersNeedsUpdate { setupParameters() }
    }

    // MARK: - Update Buffers

    func setupBuffers() {
        do {
            if let buffers = try ComputeShaderPipelineCache.getPipelineBuffers(configuration: configuration) {
                self.buffers = buffers
            }
        } catch {
            print("\(label) Compute Shader Buffers: \(error.localizedDescription)")
            if let url = configuration.pipelineURL {
                print("\(label) Compute Shader Path: \(url.path)")
            }
        }

        buffersNeedsUpdate = false
    }

    func updateBuffers() {
        if buffersNeedsUpdate { setupBuffers() }
    }

    // MARK: - Live / Compiler

    open func setupShaderCompiler() {
        guard let pipelineURL = pipelineURL else { return }
        compiler = ShaderSourceCache.getCompiler(url: pipelineURL)
        compiler.watch = live
    }

    // MARK: - Deinit

    deinit {
        resetPipeline = nil
        resetPipelineError = nil

        updatePipeline = nil
        updatePipelineError = nil
    }

    // MARK: - Clone

    public func clone() -> ComputeShader {
        print("Cloning Compute Shader: \(label)")
        let clone: ComputeShader = type(of: self).init(configuration: configuration)
        return clone
    }
}

extension ComputeShader: Equatable {
    public static func == (lhs: ComputeShader, rhs: ComputeShader) -> Bool {
        return lhs === rhs
    }
}
