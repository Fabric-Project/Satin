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

    public internal(set) var shadowPipelineError: Error?

    // MARK: - Per-Context State

    /// What this shader has made for one render context: the configuration it compiles from and
    /// its pipelines.
    private struct ContextState {
        var configuration: ShaderConfiguration?
        var pipeline: MTLRenderPipelineState?
        var pipelineError: Error?
        var usage: PipelineResourceUsage?
        var shadowUsage: PipelineResourceUsage?
        var shadowPipeline: MTLRenderPipelineState?
        var shadowPipelineError: Error?
    }

    /// The most recent pipeline resolution and its immutable binding usage.
    private var lastResolvedPipeline: MTLRenderPipelineState?
    private var lastResolvedUsage: PipelineResourceUsage?

    private func resolved(_ pipeline: MTLRenderPipelineState?, usage: PipelineResourceUsage?) -> MTLRenderPipelineState? {
        lastResolvedPipeline = pipeline
        lastResolvedUsage = usage
        return pipeline
    }

    /// Identity-check the actual returned pipeline: getPipeline overrides may substitute an
    /// unreflected state. Those keep their bindings instead of inheriting stale metadata.
    func resourceUsage(for pipeline: MTLRenderPipelineState) -> PipelineResourceUsage? {
        lastResolvedPipeline === pipeline ? lastResolvedUsage : nil
    }

    /// States in context order, with positions indexed by Context.index: no draw-time hashing.
    private var contextStates: [ContextState] = []
    private var contextStatePositions: [Int] = []

    private func contextStatePosition(for context: Context) -> Int? {
        let index = context.index
        guard index < contextStatePositions.count else { return nil }
        let position = contextStatePositions[index]
        return position < 0 ? nil : position
    }

    private func contextStatePositionAddingIfNeeded(for context: Context) -> Int {
        if let position = contextStatePosition(for: context) { return position }
        let index = context.index
        if index >= contextStatePositions.count {
            contextStatePositions.append(contentsOf: repeatElement(-1, count: index + 1 - contextStatePositions.count))
        }
        contextStates.append(ContextState())
        contextStatePositions[index] = contextStates.count - 1
        return contextStates.count - 1
    }

    /// Forgets every context's configuration and pipelines.
    func clearContextStates() {
        lastResolvedPipeline = nil
        lastResolvedUsage = nil
        contextStates.removeAll()
        contextStatePositions.removeAll()
    }

    /// The configurations compiled from so far, for a reload to invalidate what was cached for them.
    var contextConfigurations: [ShaderConfiguration] {
        contextStates.compactMap(\.configuration)
    }

    /// The pipeline already compiled for `context`, or nil if none has been yet.
    public func pipeline(for context: Context, shadow: Bool) -> MTLRenderPipelineState? {
        guard let position = contextStatePosition(for: context) else { return nil }
        return shadow
            ? resolved(contextStates[position].shadowPipeline, usage: contextStates[position].shadowUsage)
            : resolved(contextStates[position].pipeline, usage: contextStates[position].usage)
    }

    /// What selects a layout variant: plain values, so finding one compares them in turn without
    /// copying or retaining anything.
    private struct LayoutVariantKey: Equatable {
        /// The render context's interned index; equal contexts share variants.
        let contextIndex: Int
        /// The interned vertex layout: geometries with the same layout share a variant.
        let vertexLayoutID: Int
        let shadow: Bool
        let skinning: Bool
        let instancing: Bool
        let castShadow: Bool
        let receiveShadow: Bool
    }

    /// Pipelines for meshes drawn with a vertex layout, skinning, instancing or shadow settings
    /// other than the material's own; see `DrawLayout`. Parallel to `layoutVariantKeys`.
    private struct LayoutVariant {
        /// What it is compiled from, so a live reload can drop its cached libraries.
        let configuration: ShaderConfiguration
        var pipeline: MTLRenderPipelineState?
        var reflection: MTLRenderPipelineReflection?
        var usage: PipelineResourceUsage?
        /// Compiling it failed; it isn't tried again until the variants are cleared.
        var failed = false
    }

    /// The interned layout of `renderingConfiguration.vertexDescriptor`.
    private var configuredVertexLayout = InternedVertexLayout()
    /// One per distinct context, pass and layout this shader is drawn with: a handful, so every draw
    /// finds its variant by comparing a few values in turn rather than hashing a key.
    private var layoutVariants: [LayoutVariant] = []
    private var layoutVariantKeys: [LayoutVariantKey] = []
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
                clearContextStates()
                pipelineReflection = nil
                pipelineError = nil
                shadowPipelineReflection = nil
                shadowPipelineError = nil
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
        let position = contextStatePositionAddingIfNeeded(for: context)
        guard contextStates[position].configuration == nil else { return }

        configuration.context = context
        contextStates[position].configuration = configuration

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
        let position = contextStatePositionAddingIfNeeded(for: renderContext)
        if let configuration = contextStates[position].configuration {
            return configuration
        }

        var configuration = self.configuration
        configuration.context = renderContext
        contextStates[position].configuration = configuration
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
        let position = contextStatePositionAddingIfNeeded(for: renderContext)
        if shadow {
            if contextStates[position].shadowPipeline == nil,
               contextStates[position].shadowPipelineError == nil,
               castShadow
            {
                setupShadowPipeline(renderContext: renderContext)
            }
            return pipeline(for: renderContext, shadow: true)
        } else {
            if contextStates[position].pipeline == nil, contextStates[position].pipelineError == nil {
                setupPipeline(renderContext: renderContext)
            }
            return pipeline(for: renderContext, shadow: false)
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

        let key = LayoutVariantKey(
            contextIndex: renderContext.index,
            vertexLayoutID: layout.vertexLayoutID,
            shadow: shadow,
            skinning: layout.skinning,
            instancing: layout.instancing,
            castShadow: castShadow,
            receiveShadow: receiveShadow
        )
        var existingVariantIndex: Int?
        for index in layoutVariantKeys.indices where layoutVariantKeys[index] == key {
            existingVariantIndex = index
            break
        }
        if let existingVariantIndex {
            if let pipeline = layoutVariants[existingVariantIndex].pipeline { return resolved(pipeline, usage: layoutVariants[existingVariantIndex].usage) }
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
            layoutVariants.append(LayoutVariant(configuration: variantConfiguration))
            layoutVariantKeys.append(key)
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
            let usage = shadow
                ? ShaderPipelineCache.shadowUsage(configuration: variantConfiguration, pipeline: pipeline)
                : reflection.map(PipelineResourceUsage.init)
            layoutVariants[variantIndex].usage = usage
            if let reflection {
                layoutVariants[variantIndex].reflection = reflection
                addBindings(from: reflection)
            }
            return resolved(pipeline, usage: usage)
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
        layoutVariantKeys.removeAll()
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
        let position = contextStatePositionAddingIfNeeded(for: renderContext)
        guard contextStates[position].pipeline == nil, contextStates[position].pipelineError == nil else { return }
        do {
            let renderContextConfiguration = getConfiguration(renderContext: renderContext)
            let savedConfiguration = configuration
            configuration = renderContextConfiguration
            let result = try makePipeline()
            configuration = savedConfiguration
            // Compiling may have cleared every context's state (a configuration change).
            let position = contextStatePositionAddingIfNeeded(for: renderContext)
            contextStates[position].pipeline = result.pipeline
            contextStates[position].usage = result.reflection.map(PipelineResourceUsage.init)
            if pipelineReflection == nil {
                pipelineReflection = result.reflection
            }
            pipelineError = nil
            contextStates[position].pipelineError = nil
        }
        catch {
            print("\(label) Shader Pipeline: \(error.localizedDescription)")
            if let url = getConfiguration(renderContext: renderContext).pipelineURL {
                print("\(label) Shader Path: \(url.path)")
            }
            pipelineError = error
            let position = contextStatePositionAddingIfNeeded(for: renderContext)
            contextStates[position].pipelineError = error
            contextStates[position].pipeline = nil
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
        let position = contextStatePositionAddingIfNeeded(for: renderContext)
        guard contextStates[position].shadowPipeline == nil,
              contextStates[position].shadowPipelineError == nil,
              castShadow
        else { return }
        do {
            let renderConfiguration = getConfiguration(renderContext: renderContext)
            let savedConfiguration = configuration
            configuration = renderConfiguration
            defer { configuration = savedConfiguration }
            let shadowPipeline = try makeShadowPipeline()
            let position = contextStatePositionAddingIfNeeded(for: renderContext)
            contextStates[position].shadowPipeline = shadowPipeline
            contextStates[position].shadowUsage = shadowPipeline.flatMap { ShaderPipelineCache.shadowUsage(configuration: renderConfiguration, pipeline: $0) }
            shadowPipelineError = nil
            contextStates[position].shadowPipelineError = nil
        }
        catch {
            print("\(label) Shadow Shader Pipeline: \(error.localizedDescription)")
            if let url = getConfiguration(renderContext: renderContext).pipelineURL {
                print("\(label) Shader Path: \(url.path)")
            }
            shadowPipelineError = error
            let position = contextStatePositionAddingIfNeeded(for: renderContext)
            contextStates[position].shadowPipelineError = error
            contextStates[position].shadowPipeline = nil
        }

        shadowPipelineNeedsUpdate = false
    }

    deinit {
        clearContextStates()
        pipelineReflection = nil
        pipelineError = nil
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
