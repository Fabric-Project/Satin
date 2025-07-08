//
//  Shader.swift
//  Satin
//
//  Created by Reza Ali on 1/26/22.
//

import Combine
import Foundation
import Metal

open class Shader {
    // MARK: - Main Pipeline

    public internal(set) var pipelines: [Context: MTLRenderPipelineState] = [:]
    public internal(set) var pipelineError: Error?
    public internal(set) var pipelineReflection: MTLRenderPipelineReflection? {
        didSet {
            vertexBufferBindingIsUsed.removeAll()
            vertexTextureBindingIsUsed.removeAll()
            vertexWantsVertexUniforms = false
            vertexWantsMaterialUniforms = false

            fragmentBufferBindingIsUsed.removeAll()
            fragmentTextureBindingIsUsed.removeAll()
            fragmentWantsVertexUniforms = false
            fragmentWantsMaterialUniforms = false

            guard let pipelineReflection else { return }

            for binding in pipelineReflection.vertexBindings {
                if binding.type == .buffer {
                    if binding.index == VertexBufferIndex.VertexUniforms.rawValue {
                        vertexWantsVertexUniforms = binding.isUsed
                    }
                    else if binding.index == VertexBufferIndex.MaterialUniforms.rawValue {
                        vertexWantsMaterialUniforms = binding.isUsed
                    }
                    else if let bindingIndex = VertexBufferIndex(rawValue: binding.index) {
                        vertexBufferBindingIsUsed.append(bindingIndex)
                    }
                }
                else if binding.type == .texture {
                    if let bindingIndex = VertexTextureIndex(rawValue: binding.index) {
                        vertexTextureBindingIsUsed.append(bindingIndex)
                    }
                }
            }

            for binding in pipelineReflection.fragmentBindings {
                if binding.type == .buffer {
                    if binding.index == FragmentBufferIndex.VertexUniforms.rawValue {
                        fragmentWantsVertexUniforms = binding.isUsed
                    }
                    else if binding.index == FragmentBufferIndex.MaterialUniforms.rawValue {
                        fragmentWantsMaterialUniforms = binding.isUsed
                    }
                    else if let bindingIndex = FragmentBufferIndex(rawValue: binding.index) {
                        fragmentBufferBindingIsUsed.append(bindingIndex)
                    }
                }
                else if binding.type == .texture {
                    if let bindingIndex = FragmentTextureIndex(rawValue: binding.index) {
                        fragmentTextureBindingIsUsed.append(bindingIndex)
                    }
                }
            }
        }
    }

    // MARK: - Shadow Pipeline

    public internal(set) var shadowPipelines: [Context: MTLRenderPipelineState] = [:]
    public internal(set) var shadowPipelineError: Error?
    public internal(set) var shadowPipelineReflection: MTLRenderPipelineReflection?

    public internal(set) var vertexBufferBindingIsUsed: [VertexBufferIndex] = []
    public internal(set) var vertexTextureBindingIsUsed: [VertexTextureIndex] = []
    public internal(set) var vertexWantsVertexUniforms: Bool = false
    public internal(set) var vertexWantsMaterialUniforms: Bool = false

    public internal(set) var fragmentBufferBindingIsUsed: [FragmentBufferIndex] = []
    public internal(set) var fragmentTextureBindingIsUsed: [FragmentTextureIndex] = []
    public internal(set) var fragmentWantsVertexUniforms: Bool = false
    public internal(set) var fragmentWantsMaterialUniforms: Bool = false

    public var context: Context? {
        didSet {
            if let context, context != oldValue {
                setup()
            }
        }
    }

    // MARK: - Configurations

    public internal(set) var configurations: [Context: ShaderConfiguration] = [:]

    public internal(set) var renderingConfiguration = RenderingConfiguration() {
        didSet {
            if renderingConfiguration != configuration.rendering {
                configuration.rendering = renderingConfiguration
                configurationNeedsUpdate = true
            }
        }
    }

    public internal(set) var configuration: ShaderConfiguration

    var libraryURL: URL? {
        get {
            configuration.libraryURL
        }
        set {
            if configuration.libraryURL != newValue {
                configuration.libraryURL = newValue
                configurationNeedsUpdate = true
                parametersNeedsUpdate = true
            }
        }
    }

    open var constants: [String] {
        get {
            configuration.constants
        }
        set {
            if configuration.constants != newValue {
                configuration.constants = newValue
                configurationNeedsUpdate = true
            }
        }
    }

    open var defines: [ShaderDefine] {
        get {
            configuration.defines
        }
        set {
            if configuration.defines != newValue {
                configuration.defines = newValue
                configurationNeedsUpdate = true
            }
        }
    }

    // MARK: - Blending

    public var blending: Blending {
        get {
            renderingConfiguration.blending.type
        }
        set {
            renderingConfiguration.blending.type = newValue
        }
    }

    public var sourceRGBBlendFactor: MTLBlendFactor {
        get {
            renderingConfiguration.blending.sourceRGBBlendFactor
        }
        set {
            renderingConfiguration.blending.sourceRGBBlendFactor = newValue
        }
    }

    public var sourceAlphaBlendFactor: MTLBlendFactor {
        get {
            renderingConfiguration.blending.sourceAlphaBlendFactor
        }
        set {
            renderingConfiguration.blending.sourceAlphaBlendFactor = newValue
        }
    }

    public var destinationRGBBlendFactor: MTLBlendFactor {
        get {
            renderingConfiguration.blending.destinationRGBBlendFactor
        }
        set {
            renderingConfiguration.blending.destinationRGBBlendFactor = newValue
        }
    }

    public var destinationAlphaBlendFactor: MTLBlendFactor {
        get {
            configuration.rendering.blending.destinationRGBBlendFactor
        }
        set {
            renderingConfiguration.blending.destinationRGBBlendFactor = newValue
        }
    }

    public var rgbBlendOperation: MTLBlendOperation {
        get {
            renderingConfiguration.blending.rgbBlendOperation
        }
        set {
            renderingConfiguration.blending.rgbBlendOperation = newValue
        }
    }

    public var alphaBlendOperation: MTLBlendOperation {
        get {
            renderingConfiguration.blending.alphaBlendOperation
        }
        set {
            renderingConfiguration.blending.alphaBlendOperation = newValue
        }
    }

    // MARK: - Instancing

    public var instancing: Bool {
        get {
            renderingConfiguration.instancing
        }
        set {
            renderingConfiguration.instancing = newValue
        }
    }

    // MARK: - Lighting

    public var lighting: Bool {
        get {
            renderingConfiguration.lighting
        }
        set {
            renderingConfiguration.lighting = newValue
        }
    }

    public var lightCount: Int {
        get {
            renderingConfiguration.lightCount
        }
        set {
            renderingConfiguration.lightCount = newValue
        }
    }

    // MARK: - Shadows

    public var castShadow: Bool {
        get {
            renderingConfiguration.castShadow
        }
        set {
            renderingConfiguration.castShadow = newValue
        }
    }

    public var receiveShadow: Bool {
        get {
            renderingConfiguration.receiveShadow
        }
        set {
            renderingConfiguration.receiveShadow = newValue
        }
    }

    public var shadowCount: Int {
        get {
            renderingConfiguration.shadowCount
        }
        set {
            renderingConfiguration.shadowCount = newValue
        }
    }

    public var vertexDescriptor: MTLVertexDescriptor {
        get {
            renderingConfiguration.vertexDescriptor
        }
        set {
            renderingConfiguration.vertexDescriptor = newValue
        }
    }

    public var vertexFunctionName: String {
        get {
            configuration.vertexFunctionName
        }
        set {
            if configuration.vertexFunctionName != newValue {
                configuration.vertexFunctionName = newValue
                configurationNeedsUpdate = true
            }
        }
    }

    public var shadowFunctionName: String {
        get {
            configuration.shadowFunctionName
        }
        set {
            if configuration.shadowFunctionName != newValue {
                configuration.shadowFunctionName = newValue
                configurationNeedsUpdate = true
            }
        }
    }

    public var fragmentFunctionName: String {
        get {
            configuration.fragmentFunctionName
        }
        set {
            if configuration.fragmentFunctionName != newValue {
                configuration.fragmentFunctionName = newValue
                configurationNeedsUpdate = true
            }
        }
    }

    public var label: String {
        get {
            configuration.label
        }
        set {
            if configuration.label != newValue {
                configuration.label = newValue
                configurationNeedsUpdate = true
                parametersNeedsUpdate = true
            }
        }
    }

    public var configurationNeedsUpdate = true {
        didSet {
            if configurationNeedsUpdate {
                configurations.removeAll()
                pipelines.removeAll()
                shadowPipelines.removeAll()
            }
        }
    }

    public var definesNeedsUpdate = true {
        didSet {
            if definesNeedsUpdate {
                configurationNeedsUpdate = true
            }
        }
    }

    public var constantsNeedsUpdate = true {
        didSet {
            if constantsNeedsUpdate {
                configurationNeedsUpdate = true
            }
        }
    }

    public var shadowPipelineNeedsUpdate = false
    public var pipelineNeedsUpdate = true
    public var parametersNeedsUpdate = true

    public let parametersPublisher = PassthroughSubject<ParameterGroup, Never>()

    public var parameters: ParameterGroup? {
        didSet {
            if let parameters {
                parametersPublisher.send(parameters)
            }
        }
    }

    public required init(configuration: ShaderConfiguration) {
        self.configuration = configuration
    }

    public init(
        label: String,
        vertexFunctionName: String? = nil,
        fragmentFunctionName: String? = nil,
        shadowFunctionName: String? = nil,
        libraryURL: URL? = nil,
        pipelineURL: URL? = nil
    ) {
        configuration = ShaderConfiguration(
            label: label,
            vertexFunctionName: vertexFunctionName ?? label.camelCase + "Vertex",
            fragmentFunctionName: fragmentFunctionName ?? label.camelCase + "Fragment",
            shadowFunctionName: shadowFunctionName ?? label.camelCase + "ShadowVertex",
            libraryURL: libraryURL,
            pipelineURL: pipelineURL
        )
    }

    public func setup() {
        updateDefines()
        updateConstants()

        setupConfiguration()

        setupPipeline()
        setupShadowPipeline()
        updateParameters()
    }

    public func update() {
        updateDefines()
        updateConstants()

        updateConfiguration()

        updatePipeline()
        updateShadowPipeline()
        updateParameters()
    }

    // MARK: - Configuration

    func setupConfiguration() {
        guard let context, configurations[context] == nil else { return }

        configuration.context = context
        configurations[context] = configuration

        pipelineNeedsUpdate = true
        shadowPipelineNeedsUpdate = true

        configurationNeedsUpdate = false
    }

    func updateConfiguration() {
        if configurationNeedsUpdate {
            setupConfiguration()
        }
    }

    // MARK: - Defines

    open func getDefines() -> [ShaderDefine] {
        return []
    }

    func updateDefines() {
        guard definesNeedsUpdate else { return }
        defines = getDefines()
        definesNeedsUpdate = false
    }

    // MARK: - Constants

    open func getConstants() -> [String] {
        []
    }

    func updateConstants() {
        guard constantsNeedsUpdate else { return }
        constants = getConstants()
        constantsNeedsUpdate = false
    }

    // MARK: - Parameters

    func updateParameters() {
        guard parametersNeedsUpdate else { return }
        do {
            if let pipelineParameters = try ShaderPipelineCache.getPipelineParameters(configuration: configuration) {
                parameters = pipelineParameters
            }
        }
        catch {
            print("\(label) Shader Parameters: \(error.localizedDescription)")
            if let url = configuration.pipelineURL {
                print("\(label) Shader Path: \(url.path)")
            }
        }

        parametersNeedsUpdate = false
    }

    // MARK: - Pipelines

    open func getPipeline(renderContext: Context, shadow: Bool) -> MTLRenderPipelineState? {
        shadow ? shadowPipelines[renderContext] : pipelines[renderContext]
    }

    func updatePipeline() {
        if pipelineNeedsUpdate {
            setupPipeline()
        }
    }

    open func makePipeline() throws -> (pipeline: MTLRenderPipelineState?, reflection: MTLRenderPipelineReflection?) {
        try ShaderPipelineCache.getPipeline(configuration: configuration)
    }

    func setupPipeline() {
        guard let context, pipelines[context] == nil, pipelineError == nil else { return }
        do {
            let result = try makePipeline()
            pipelines[context] = result.pipeline
            pipelineReflection = result.reflection
            pipelineError = nil
        }
        catch {
            print("\(label) Shader Pipeline: \(error.localizedDescription)")
            if let url = configuration.pipelineURL {
                print("\(label) Shader Path: \(url.path)")
            }
            pipelineError = error
            pipelineReflection = nil
            pipelines[context] = nil
        }
        pipelineNeedsUpdate = false
    }

    func updateShadowPipeline() {
        if shadowPipelineNeedsUpdate {
            setupShadowPipeline()
        }
    }

    open func makeShadowPipeline() throws -> MTLRenderPipelineState? {
        try ShaderPipelineCache.getShadowPipeline(configuration: configuration)
    }

    func setupShadowPipeline() {
        guard let context, shadowPipelines[context] == nil, shadowPipelineError == nil, castShadow else { return }
        do {
            shadowPipelines[context] = try makeShadowPipeline()
            shadowPipelineError = nil
        }
        catch {
            print("\(label) Shadow Shader Pipeline: \(error.localizedDescription)")
            if let url = configuration.pipelineURL {
                print("\(label) Shader Path: \(url.path)")
            }
            shadowPipelineError = error
            shadowPipelines[context] = nil
        }

        shadowPipelineNeedsUpdate = false
    }

    deinit {
        configurations.removeAll()

        pipelines.removeAll()
        pipelineReflection = nil
        pipelineError = nil

        shadowPipelines.removeAll()
        shadowPipelineReflection = nil
        shadowPipelineError = nil
    }

    public func clone() -> Shader {
        let clone: Shader = type(of: self).init(configuration: configuration)
        return clone
    }
}

extension Shader: Equatable {
    public static func == (lhs: Shader, rhs: Shader) -> Bool {
        return lhs === rhs
    }
}
