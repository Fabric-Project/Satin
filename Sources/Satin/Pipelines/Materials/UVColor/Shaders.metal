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
                   instanceUniforms[instanceID].modelMatrix * SATIN_SKIN_POSITION(in);
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * SATIN_SKIN_POSITION(in);
#endif

#if defined(HAS_TEXCOORD)
    out.texcoord = in.texcoord;
#else
    // Layouts without texture coordinates, such as points, get zero.
    out.texcoord = float2(0.0);
#endif
    out.pointSize = SATIN_POINT_SIZE(in, uniforms.pointSize);
    return out;
}

fragment half4 uvcolorFragment(UVColorVertexData in [[stage_in]]
    SATIN_POINT_SPRITE_FRAGMENT_DATA) {
    return SATIN_POINT_SPRITE(half4(half2(in.texcoord), 0.0h, 1.0h));
}
