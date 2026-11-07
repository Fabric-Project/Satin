#include "../../Includes/FragmentOutput.metal"

typedef struct {
    float4 color;     // color
    float pointSize;  // slider,1.0,64.0,1.0
} BasicColorUniforms;

typedef struct {
    float4 position [[position]];
    float pointSize [[point_size]];
#if defined(HAS_COLOR)
    float4 color;
#endif
} BasicColorVertexData;

vertex BasicColorVertexData basicColorVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant BasicColorUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {
    BasicColorVertexData out;

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix *
                   instanceUniforms[instanceID].modelMatrix * SATIN_SKIN_POSITION(in);
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * SATIN_SKIN_POSITION(in);
#endif

    out.pointSize = uniforms.pointSize;
#if defined(HAS_COLOR)
    out.color = in.color;
#endif
    return out;
}

fragment FragmentOutput basicColorFragment(
    BasicColorVertexData in [[stage_in]],
    constant BasicColorUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]
    SATIN_ALPHA_OIT_FRAGMENT_DATA) {
#if defined(HAS_COLOR)
    const float4 color = uniforms.color * in.color;
#else
    const float4 color = uniforms.color;
#endif
    return buildColorFragmentOutput(half4(color) SATIN_ALPHA_OIT_FORWARD_ARGS);
}
