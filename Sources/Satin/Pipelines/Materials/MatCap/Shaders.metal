#include "Library/TextureTransform.metal"

typedef struct {
    float4 position [[position]];
    float3 eye;
    float3 normal;
    float pointSize [[point_size]];
#if defined(HAS_COLOR)
    float4 color;
#endif
} MatCapVertexData;

typedef struct {
    float4 color; // color
    float4x4 textureTransform;
    float pointSize; // slider,1.0,64.0,1.0
} MatCapUniforms;

vertex MatCapVertexData matCapVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant MatCapUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {
#if INSTANCING
    const float4x4 modelViewMatrix =
        vertexUniforms[amp_id].viewMatrix * instanceUniforms[instanceID].modelMatrix;
#else
    const float4x4 modelViewMatrix = vertexUniforms[amp_id].modelViewMatrix;
#endif

    const float4 screenSpaceNormal = modelViewMatrix * float4(SATIN_SKIN_NORMAL(in), 0.0);
    const float4 worldPosition = modelViewMatrix * SATIN_SKIN_POSITION(in);
    const float3 eye = normalize(worldPosition.xyz);

    MatCapVertexData out;
    out.position = vertexUniforms[amp_id].projectionMatrix * worldPosition;
    out.eye = eye;
    out.normal = screenSpaceNormal.xyz;
    out.pointSize = SATIN_POINT_SIZE(in, uniforms.pointSize);
#if defined(HAS_COLOR)
    out.color = in.color;
#endif
    return out;
}

fragment half4 matCapFragment(
    MatCapVertexData in [[stage_in]],
    constant MatCapUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float> tex [[texture(FragmentTextureCustom0)]],
    sampler texSampler [[sampler(FragmentSamplerCustom0)]]
    SATIN_POINT_SPRITE_FRAGMENT_DATA) {
    const float3 r = reflect(in.eye, normalize(in.normal));
    const float m = 2.0 * sqrt(pow(r.x, 2.0) + pow(r.y, 2.0) + pow(r.z + 1.0, 2.0));
    const float2 uv = applyTextureTransform(r.xy / m + 0.5, uniforms.textureTransform);
#if defined(HAS_COLOR)
    return half4(SATIN_POINT_SPRITE(uniforms.color * in.color * tex.sample(texSampler, uv)));
#else
    return half4(SATIN_POINT_SPRITE(uniforms.color * tex.sample(texSampler, uv)));
#endif
}
