#include "../../Includes/FragmentOutput.metal"

typedef struct {
    float4 color;     // color
    float pointSize;  // slider,1.0,64.0,1.0
} BasicColorUniforms;

typedef struct {
    float4 position [[position]];
    float pointSize [[point_size]];
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
                   instanceUniforms[instanceID].modelMatrix * float4(in.position, 1.0);
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * float4(in.position, 1.0);
#endif

    out.pointSize = uniforms.pointSize;
    return out;
}

fragment FragmentOutput basicColorFragment(
    BasicColorVertexData in [[stage_in]],
    constant BasicColorUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]
    SATIN_ALPHA_OIT_FRAGMENT_DATA) {
    return buildColorFragmentOutput(half4(uniforms.color) SATIN_ALPHA_OIT_FORWARD_ARGS);
}
