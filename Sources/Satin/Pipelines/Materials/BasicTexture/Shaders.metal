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
                   instanceUniforms[instanceID].modelMatrix * float4(in.position, 1.0);
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * float4(in.position, 1.0);
#endif

    out.texcoord = in.texcoord;
    out.pointSize = uniforms.pointSize;
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

    return buildColorFragmentOutput(half4(uniforms.color * texSample) SATIN_ALPHA_OIT_FORWARD_ARGS);
}
