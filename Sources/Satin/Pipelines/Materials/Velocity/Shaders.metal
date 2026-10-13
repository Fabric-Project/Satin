typedef struct {
    float4 position [[position]];
    float4 currentClipPos;
    float4 previousClipPos;
} VelocityVertexData;

vertex VelocityVertexData velocityVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
    VelocityVertexData out;
#if INSTANCING
    const float4x4 modelMatrix = instanceUniforms[instanceID].modelMatrix;
    out.currentClipPos = vertexUniforms[amp_id].viewProjectionMatrix * modelMatrix * SATIN_SKIN_POSITION(in);
#else
    out.currentClipPos = vertexUniforms[amp_id].modelViewProjectionMatrix * SATIN_SKIN_POSITION(in);
#endif
    out.previousClipPos = SATIN_PREVIOUS_CLIP_POSITION(in);

    out.position = out.currentClipPos;
    return out;
}

fragment half2 velocityFragment(VelocityVertexData in [[stage_in]]) {
    const float2 current = in.currentClipPos.xy / in.currentClipPos.w;
    const float2 previous = in.previousClipPos.xy / in.previousClipPos.w;
    const float2 delta = current - previous;
    // Convert NDC delta (+Y up) to UV delta (+V down) so downstream sampling offsets operate
    // in texture coordinates rather than clip-space.
    return half2(delta.x * 0.5h, -delta.y * 0.5h);
}
