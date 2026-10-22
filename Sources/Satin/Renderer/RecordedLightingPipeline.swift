import Metal

/// Values captured at the material's draw hook. Only target-wide lighting counts are supplied
/// after every occurrence is known; no live material or shader is read during finalization.
struct RecordedLightingPipeline {
    let shaderType: Shader.Type
    let configuration: ShaderConfiguration
    let renderContext: Context
    let layout: DrawLayout?

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

    func resolve(lightCount: Int, shadowCount: Int, shadowTextureCount: Int, projectorCount: Int) -> MTLRenderPipelineState? {
        var configuration = configuration
        configuration.rendering.lightCount = lightCount
        configuration.rendering.directShadowCount = shadowCount
        configuration.rendering.directShadowTextureCount = shadowTextureCount
        configuration.rendering.projectorCount = projectorCount
        let shader = shaderType.init(configuration: configuration)
        return shader.getPipeline(renderContext: renderContext, shadow: false, layout: layout)
    }
}
