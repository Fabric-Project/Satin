#include "Library/TextureTransform.metal"
#include "../../Includes/FragmentOutput.metal"

typedef struct {
    float4 color; // color
    float4x4 textureTransform;
    float pointSize; // slider,1.0,64.0,1.0
} BasicTextureUniforms;

typedef struct {
    float4 position [[position]];
    float2 texcoord;
    float pointSize [[point_size]];
#if defined(HAS_COLOR)
    float4 color;
#endif
} BasicTextureVertexData;

vertex BasicTextureVertexData basicTextureVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant BasicTextureUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {
    BasicTextureVertexData out;

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix *
                   instanceUniforms[instanceID].modelMatrix * SATIN_SKIN_POSITION(in);
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * SATIN_SKIN_POSITION(in);
#endif

    out.texcoord = in.texcoord;
    out.pointSize = uniforms.pointSize;
#if defined(HAS_COLOR)
    out.color = in.color;
#endif
    return out;
}

fragment FragmentOutput basicTextureFragment(
    BasicTextureVertexData in [[stage_in]],
    constant BasicTextureUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float> tex [[texture(FragmentTextureCustom0)]],
    sampler texSampler [[sampler(FragmentSamplerCustom0)]]
    SATIN_ALPHA_OIT_FRAGMENT_DATA) {
    const float2 uv = applyTextureTransform(in.texcoord, uniforms.textureTransform);
    const float4 texSample = tex.sample(texSampler, uv);
    if (texSample.a == 0.0) { discard_fragment(); }

#if defined(HAS_COLOR)
    const float4 color = uniforms.color * in.color * texSample;
#else
    const float4 color = uniforms.color * texSample;
#endif
    return buildColorFragmentOutput(half4(color) SATIN_ALPHA_OIT_FORWARD_ARGS);
}
