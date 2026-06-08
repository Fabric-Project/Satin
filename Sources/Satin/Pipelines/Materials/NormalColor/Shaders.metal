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
                   instanceUniforms[instanceID].modelMatrix * float4(in.position, 1.0);
    out.normal = instanceUniforms[instanceID].normalMatrix * in.normal;
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * float4(in.position, 1.0);
    out.normal = vertexUniforms[amp_id].normalMatrix * in.normal;
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
