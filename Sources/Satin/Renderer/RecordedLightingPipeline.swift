import Metal

/// A captured configuration shared across recordings. Finalization supplies only target-wide
/// lighting counts; it never reads the source shader's current configuration.
struct RecordedLightingPipeline {
    private let state: RecordedLightingPipelineState
    var configuration: ShaderConfiguration { state.configuration }

    init(shader: Shader, renderContext: Context, layout: DrawLayout?) {
        if let state = shader.recordedLightingPipelines.first(where: {
            $0.matches(shader: shader, renderContext: renderContext, layout: layout)
        }) {
            self.state = state
        } else {
            let state = RecordedLightingPipelineState(shader: shader, renderContext: renderContext, layout: layout)
            shader.recordedLightingPipelines.append(state)
            self.state = state
        }
    }

    func resolve(lightCount: Int, shadowCount: Int, shadowTextureCount: Int, projectorCount: Int) -> MTLRenderPipelineState? {
        state.resolve(counts: .init(lights: lightCount, shadows: shadowCount,
                                   shadowTextures: shadowTextureCount, projectors: projectorCount))
    }
}

/// Owned by the source shader and any outstanding recordings. Arrays contain only the distinct
/// configurations and lighting variants actually used; steady-state resolution never hashes.
final class RecordedLightingPipelineState {
    struct Counts: Equatable {
        let lights: Int
        let shadows: Int
        let shadowTextures: Int
        let projectors: Int
    }

    private struct Variant {
        let counts: Counts
        let shader: Shader
        let pipeline: MTLRenderPipelineState?
    }

    private let shaderType: Shader.Type
    let configuration: ShaderConfiguration
    private let renderContext: Context
    private let layout: DrawLayout?
    private var variants: [Variant] = []

    init(shader: Shader, renderContext: Context, layout: DrawLayout?) {
        shaderType = type(of: shader)
        var configuration = shader.configuration
        if let descriptor = configuration.rendering.vertexDescriptor.copy() as? MTLVertexDescriptor {
            configuration.rendering.vertexDescriptor = descriptor
        }
        self.configuration = configuration
        self.renderContext = renderContext
        if let layout, let descriptor = layout.vertexDescriptor.copy() as? MTLVertexDescriptor {
            self.layout = DrawLayout(vertexDescriptor: descriptor, vertexLayoutID: layout.vertexLayoutID,
                                     skinning: layout.skinning, instancing: layout.instancing,
                                     castShadow: layout.castShadow, receiveShadow: layout.receiveShadow)
        } else {
            self.layout = layout
        }
    }

    /// The shader revision this state last matched: an unchanged shader matches again without
    /// comparing (and copying) its whole configuration on every draw.
    private var matchedConfigurationRevision: UInt64?

    func matches(shader: Shader, renderContext: Context, layout: DrawLayout?) -> Bool {
        guard self.renderContext.index == renderContext.index else { return false }
        switch (self.layout, layout) {
        case (nil, nil): break
        case let (stored?, incoming?):
            guard stored.vertexLayoutID == incoming.vertexLayoutID,
                  stored.skinning == incoming.skinning, stored.instancing == incoming.instancing,
                  stored.castShadow == incoming.castShadow, stored.receiveShadow == incoming.receiveShadow
            else { return false }
        default: return false
        }
        if matchedConfigurationRevision == shader.configurationRevision { return true }
        guard self.configuration == shader.configuration else { return false }
        matchedConfigurationRevision = shader.configurationRevision
        return true
    }

    func resolve(counts: Counts) -> MTLRenderPipelineState? {
        for variant in variants where variant.counts == counts { return variant.pipeline }
        var configuration = configuration
        configuration.rendering.lightCount = counts.lights
        configuration.rendering.directShadowCount = counts.shadows
        configuration.rendering.directShadowTextureCount = counts.shadowTextures
        configuration.rendering.projectorCount = counts.projectors
        let shader = shaderType.init(configuration: configuration)
        let pipeline = shader.getPipeline(renderContext: renderContext, shadow: false, layout: layout)
        variants.append(Variant(counts: counts, shader: shader, pipeline: pipeline))
        return pipeline
    }

    func invalidateCachedSources() {
        for variant in variants {
            for configuration in variant.shader.contextConfigurations {
                ShaderLibrarySourceCache.invalidateLibrarySource(configuration: configuration.getLibraryConfiguration())
                ShaderLibraryCache.invalidateLibrary(configuration: configuration.getLibraryConfiguration())
                ShaderPipelineCache.invalidate(configuration: configuration)
            }
            variant.shader.invalidateLayoutVariants()
        }
    }
}
