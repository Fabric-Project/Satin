typedef struct {
    float4 color; // color,0,0,0,0.25
} ShadowUniforms;

typedef struct {
    float4 position [[position]];
} ShadowVertexData;

vertex ShadowVertexData shadowVertex(
    Vertex in [[stage_in]],
    ushort amp_id [[amplification_id]],
    // inject instancing args
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
    ShadowVertexData out;

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix *
                   instanceUniforms[instanceID].modelMatrix * float4(in.position, 1.0);
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * float4(in.position, 1.0);
#endif

    return out;
}

fragment float4 shadowFragment(
    ShadowVertexData in [[stage_in]],
    // inject shadow fragment args
    constant ShadowUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
    float4 outColor = 0.0;
    // inject shadow fragment calc
    outColor = uniforms.color;
#if defined(SHADOW_COUNT)
    outColor.a *= 1.0 - shadow;
#else
    outColor.a *= 0.0;
#endif
    return outColor;
}
