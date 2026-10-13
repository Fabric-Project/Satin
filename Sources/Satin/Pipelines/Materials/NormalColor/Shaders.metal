typedef struct {
    bool absolute;   // toggle
    float pointSize; // slider,1.0,64.0,1.0
} NormalColorUniforms;

typedef struct {
    float4 position [[position]];
    float3 normal;
    float pointSize [[point_size]];
} NormalColorVertexData;

vertex NormalColorVertexData normalColorVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant NormalColorUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {
    NormalColorVertexData out;

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix *
                   instanceUniforms[instanceID].modelMatrix * SATIN_SKIN_POSITION(in);
    out.normal = instanceUniforms[instanceID].normalMatrix * SATIN_SKIN_NORMAL(in);
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * SATIN_SKIN_POSITION(in);
    out.normal = vertexUniforms[amp_id].normalMatrix * SATIN_SKIN_NORMAL(in);
#endif

    out.pointSize = uniforms.pointSize;
    return out;
}

fragment half4 normalColorFragment(
    NormalColorVertexData in [[stage_in]],
    constant NormalColorUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
    const float3 normal = normalize(in.normal);
    return half4(half3(mix(normal, abs(normal), float(uniforms.absolute))), 1.0h);
}
