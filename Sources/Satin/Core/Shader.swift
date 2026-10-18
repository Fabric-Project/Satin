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

    public internal(set) var pipelines: [UUID: MTLRenderPipelineState] = [:]
    public internal(set) var pipelineError: Error?
    var pipelineErrors: [UUID: Error] = [:]
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

            if let pipelineReflection { addBindings(from: pipelineReflection) }
            // Variant pipelines may use resources the base one does not; bind for them too.
            for variant in layoutVariants {
                if let reflection = variant.reflection { addBindings(from: reflection) }
            }
        }
    }

    /// Adds the buffers and textures a pipeline uses to the bindings materials make for it.
    private func addBindings(from pipelineReflection: MTLRenderPipelineReflection) {
        for binding in pipelineReflection.vertexBindings {
            if binding.type == .buffer {
                if binding.index == VertexBufferIndex.VertexUniforms.rawValue {
                    vertexWantsVertexUniforms = vertexWantsVertexUniforms || binding.isUsed
                }
                else if binding.index == VertexBufferIndex.MaterialUniforms.rawValue {
                    vertexWantsMaterialUniforms = vertexWantsMaterialUniforms || binding.isUsed
                }
                else if let bindingIndex = VertexBufferIndex(rawValue: binding.index), !vertexBufferBindingIsUsed.contains(bindingIndex) {
                    vertexBufferBindingIsUsed.append(bindingIndex)
                }
            }
            else if binding.type == .texture {
                if let bindingIndex = VertexTextureIndex(rawValue: binding.index), !vertexTextureBindingIsUsed.contains(bindingIndex) {
                    vertexTextureBindingIsUsed.append(bindingIndex)
                }
            }
        }

        for binding in pipelineReflection.fragmentBindings {
            if binding.type == .buffer {
                if binding.index == FragmentBufferIndex.VertexUniforms.rawValue {
                    fragmentWantsVertexUniforms = fragmentWantsVertexUniforms || binding.isUsed
                }
                else if binding.index == FragmentBufferIndex.MaterialUniforms.rawValue {
                    fragmentWantsMaterialUniforms = fragmentWantsMaterialUniforms || binding.isUsed
                }
                else if let bindingIndex = FragmentBufferIndex(rawValue: binding.index), !fragmentBufferBindingIsUsed.contains(bindingIndex) {
                    fragmentBufferBindingIsUsed.append(bindingIndex)
                }
            }
            else if binding.type == .texture {
                if let bindingIndex = FragmentTextureIndex(rawValue: binding.index), !fragmentTextureBindingIsUsed.contains(bindingIndex) {
                    fragmentTextureBindingIsUsed.append(bindingIndex)
                }
            }
        }
    }

    // MARK: - Shadow Pipeline

    public internal(set) var shadowPipelines: [UUID: MTLRenderPipelineState] = [:]
    public internal(set) var shadowPipelineError: Error?
    var shadowPipelineErrors: [UUID: Error] = [:]

    /// Pipelines for meshes drawn with a vertex layout, skinning, instancing or shadow settings
    /// other than the material's own; see `DrawLayout`.
    private struct LayoutVariant {
        let contextID: UUID
        let shadow: Bool
        let skinning: Bool
        let instancing: Bool
        let castShadow: Bool
        let receiveShadow: Bool
        /// The interned vertex layout: geometries with the same layout share a variant.
        let vertexLayoutID: Int
        /// What it is compiled from, so a live reload can drop its cached libraries.
        let configuration: ShaderConfiguration
        var pipeline: MTLRenderPipelineState?
        var reflection: MTLRenderPipelineReflection?
        /// Compiling it failed; it isn't tried again until the variants are cleared.
        var failed = false
    }

    /// The interned layout of `renderingConfiguration.vertexDescriptor`.
    private var configuredVertexLayout = InternedVertexLayout()
    /// One per distinct context, pass and layout this shader is drawn with: a handful, so every draw
    /// finds its variant by comparing a few values in turn rather than hashing a key.
    private var layoutVariants: [LayoutVariant] = []
    public internal(set) var shadowPipelineReflection: MTLRenderPipelineReflection?

    public internal(set) var vertexBufferBindingIsUsed: [VertexBufferIndex] = []
    public internal(set) var vertexTextureBindingIsUsed: [VertexTextureIndex] = []
    public internal(set) var vertexWantsVertexUniforms: Bool = false
    public internal(set) var vertexWantsMaterialUniforms: Bool = false

    public internal(set) var fragmentBufferBindingIsUsed: [FragmentBufferIndex] = []
    public internal(set) var fragmentTextureBindingIsUsed: [FragmentTextureIndex] = []
    public internal(set) var fragmentWantsVertexUniforms: Bool = false
    public internal(set) var fragmentWantsMaterialUniforms: Bool = false

    public let context: Context

    // MARK: - Configurations

    public internal(set) var configurations: [UUID: ShaderConfiguration] = [:]

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

    public var directShadowCount: Int {
        get {
            renderingConfiguration.directShadowCount
        }
        set {
            renderingConfiguration.directShadowCount = newValue
        }
    }

    public var directShadowTextureCount: Int {
        get {
            renderingConfiguration.directShadowTextureCount
        }
        set {
            renderingConfiguration.directShadowTextureCount = newValue
        }
    }

    public var projectorCount: Int {
        get {
            renderingConfiguration.projectorCount
        }
        set {
            renderingConfiguration.projectorCount = newValue
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
                pipelineReflection = nil
                pipelineError = nil
                pipelineErrors.removeAll()
                shadowPipelines.removeAll()
                shadowPipelineReflection = nil
                shadowPipelineError = nil
                shadowPipelineErrors.removeAll()
                clearLayoutVariants()
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
        guard let ctx = configuration.context else {
            preconditionFailure("\(Self.self) requires ShaderConfiguration.context to be non-nil")
        }
        self.context = ctx
        self.configuration = configuration
    }

    public convenience init(context: Context, configuration: ShaderConfiguration) {
        var configuration = configuration
        configuration.context = context
        self.init(configuration: configuration)
    }

    public convenience init(
        context: Context,
        label: String,
        vertexFunctionName: String? = nil,
        fragmentFunctionName: String? = nil,
        shadowFunctionName: String? = nil,
        libraryURL: URL? = nil,
        pipelineURL: URL? = nil
    ) {
        var configuration = ShaderConfiguration(
            label: label,
            vertexFunctionName: vertexFunctionName ?? label.camelCase + "Vertex",
            fragmentFunctionName: fragmentFunctionName ?? label.camelCase + "Fragment",
            shadowFunctionName: shadowFunctionName ?? label.camelCase + "ShadowVertex",
            libraryURL: libraryURL,
            pipelineURL: pipelineURL
        )
        configuration.context = context
        self.init(configuration: configuration)
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
        guard configurations[context.id] == nil else { return }

        configuration.context = context
        configurations[context.id] = configuration

        pipelineNeedsUpdate = true
        shadowPipelineNeedsUpdate = true

        configurationNeedsUpdate = false
    }

    func updateConfiguration() {
        if configurationNeedsUpdate {
            setupConfiguration()
        }
    }

    func getConfiguration(renderContext: Context) -> ShaderConfiguration {
        if let configuration = configurations[renderContext.id] {
            return configuration
        }

        var configuration = self.configuration
        configuration.context = renderContext
        configurations[renderContext.id] = configuration
        return configuration
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
        if shadow {
            if shadowPipelines[renderContext.id] == nil,
               shadowPipelineErrors[renderContext.id] == nil,
               castShadow
            {
                setupShadowPipeline(renderContext: renderContext)
            }
            return shadowPipelines[renderContext.id]
        } else {
            if pipelines[renderContext.id] == nil, pipelineErrors[renderContext.id] == nil {
                setupPipeline(renderContext: renderContext)
            }
            return pipelines[renderContext.id]
        }
    }

    /// The pipeline for drawing a mesh with `layout`: the shader's own when every setting
    /// matches its configuration, otherwise a variant compiled for them.
    open func getPipeline(renderContext: Context, shadow: Bool, layout: DrawLayout?) -> MTLRenderPipelineState? {
        guard let layout else { return getPipeline(renderContext: renderContext, shadow: shadow) }
        // Only casters have a shadow pipeline.
        if shadow, !layout.castShadow { return nil }
        // Casting changes only the shadow pipeline and receiving only the color one, so each pass
        // keeps the shader's own setting for the other and shares its pipeline across both kinds of mesh.
        let castShadow = shadow ? layout.castShadow : renderingConfiguration.castShadow
        let receiveShadow = shadow ? renderingConfiguration.receiveShadow : layout.receiveShadow
        guard layout.skinning != renderingConfiguration.skinning
              || layout.instancing != renderingConfiguration.instancing
              || castShadow != renderingConfiguration.castShadow
              || receiveShadow != renderingConfiguration.receiveShadow
              || layout.vertexLayoutID != configuredVertexLayout.layoutID(for: renderingConfiguration.vertexDescriptor)
        else { return getPipeline(renderContext: renderContext, shadow: shadow) }

        let contextID = renderContext.id
        let existingVariantIndex = layoutVariants.firstIndex { variant in
            variant.vertexLayoutID == layout.vertexLayoutID
                && variant.shadow == shadow
                && variant.skinning == layout.skinning
                && variant.instancing == layout.instancing
                && variant.castShadow == castShadow
                && variant.receiveShadow == receiveShadow
                && variant.contextID == contextID
        }
        if let existingVariantIndex {
            if let pipeline = layoutVariants[existingVariantIndex].pipeline { return pipeline }
            if layoutVariants[existingVariantIndex].failed { return nil }
        }

        var variantConfiguration = getConfiguration(renderContext: renderContext)
        variantConfiguration.rendering.skinning = layout.skinning
        variantConfiguration.rendering.instancing = layout.instancing
        variantConfiguration.rendering.castShadow = castShadow
        variantConfiguration.rendering.receiveShadow = receiveShadow
        variantConfiguration.rendering.vertexDescriptor = layout.vertexDescriptor
        let savedConfiguration = configuration
        configuration = variantConfiguration
        defer { configuration = savedConfiguration }

        let variantIndex: Int
        if let existingVariantIndex {
            variantIndex = existingVariantIndex
        } else {
            variantIndex = layoutVariants.count
            layoutVariants.append(
                LayoutVariant(
                    contextID: contextID,
                    shadow: shadow,
                    skinning: layout.skinning,
                    instancing: layout.instancing,
                    castShadow: castShadow,
                    receiveShadow: receiveShadow,
                    vertexLayoutID: layout.vertexLayoutID,
                    configuration: variantConfiguration
                )
            )
        }

        do {
            let pipeline: MTLRenderPipelineState?
            var reflection: MTLRenderPipelineReflection?
            if shadow {
                pipeline = try makeShadowPipeline()
            } else {
                (pipeline, reflection) = try makePipeline()
            }
            guard let pipeline else { return nil }
            // A configuration change while compiling clears the variants; the result is then not kept.
            guard variantIndex < layoutVariants.count else { return pipeline }
            // Unbounded, as ShaderPipelineCache is: variants grow only with the distinct layouts this
            // shader is drawn with, not with geometries.
            layoutVariants[variantIndex].pipeline = pipeline
            if let reflection {
                layoutVariants[variantIndex].reflection = reflection
                addBindings(from: reflection)
            }
            return pipeline
        } catch {
            print("\(label) Shader Pipeline (layout variant): \(error.localizedDescription)")
            if variantIndex < layoutVariants.count {
                layoutVariants[variantIndex].failed = true
            }
            return nil
        }
    }

    /// Drops every layout variant and its cached source, library and pipeline, as a live
    /// reload does for the base pipelines.
    func invalidateLayoutVariants() {
        for variant in layoutVariants {
            ShaderLibrarySourceCache.invalidateLibrarySource(configuration: variant.configuration.getLibraryConfiguration())
            ShaderLibraryCache.invalidateLibrary(configuration: variant.configuration.getLibraryConfiguration())
            ShaderPipelineCache.invalidate(configuration: variant.configuration)
        }
        clearLayoutVariants()
    }

    private func clearLayoutVariants() {
        layoutVariants.removeAll()
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
        setupPipeline(renderContext: context)
    }

    func setupPipeline(renderContext: Context) {
        guard pipelines[renderContext.id] == nil, pipelineErrors[renderContext.id] == nil else { return }
        do {
            let renderContextConfiguration = getConfiguration(renderContext: renderContext)
            let savedConfiguration = configuration
            configuration = renderContextConfiguration
            let result = try makePipeline()
            configuration = savedConfiguration
            pipelines[renderContext.id] = result.pipeline
            if pipelineReflection == nil {
                pipelineReflection = result.reflection
            }
            pipelineError = nil
            pipelineErrors[renderContext.id] = nil
        }
        catch {
            print("\(label) Shader Pipeline: \(error.localizedDescription)")
            if let url = getConfiguration(renderContext: renderContext).pipelineURL {
                print("\(label) Shader Path: \(url.path)")
            }
            pipelineError = error
            pipelineErrors[renderContext.id] = error
            pipelines[renderContext.id] = nil
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
        setupShadowPipeline(renderContext: context)
    }

    func setupShadowPipeline(renderContext: Context) {
        guard shadowPipelines[renderContext.id] == nil,
              shadowPipelineErrors[renderContext.id] == nil,
              castShadow
        else { return }
        do {
            shadowPipelines[renderContext.id] = try ShaderPipelineCache.getShadowPipeline(configuration: getConfiguration(renderContext: renderContext))
            shadowPipelineError = nil
            shadowPipelineErrors[renderContext.id] = nil
        }
        catch {
            print("\(label) Shadow Shader Pipeline: \(error.localizedDescription)")
            if let url = getConfiguration(renderContext: renderContext).pipelineURL {
                print("\(label) Shader Path: \(url.path)")
            }
            shadowPipelineError = error
            shadowPipelineErrors[renderContext.id] = error
            shadowPipelines[renderContext.id] = nil
        }

        shadowPipelineNeedsUpdate = false
    }

    deinit {
        configurations.removeAll()

        pipelines.removeAll()
        pipelineReflection = nil
        pipelineError = nil
        pipelineErrors.removeAll()

        shadowPipelines.removeAll()
        shadowPipelineReflection = nil
        shadowPipelineError = nil
        shadowPipelineErrors.removeAll()
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
