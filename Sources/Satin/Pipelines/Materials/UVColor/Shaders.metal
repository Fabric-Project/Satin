typedef struct {
    float pointSize; // slider,1.0,64.0,1.0
} UVColorUniforms;

typedef struct {
    float4 position [[position]];
    float2 texcoord;
    float pointSize [[point_size]];
} UVColorVertexData;

vertex UVColorVertexData uvcolorVertex(
    Vertex in [[stage_in]],
    ushort amp_id [[amplification_id]],
    // inject instancing args
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant UVColorUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {
    UVColorVertexData out;

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

fragment half4 uvcolorFragment(UVColorVertexData in [[stage_in]]) {
    return half4(half2(in.texcoord), 0.0h, 1.0h);
}
