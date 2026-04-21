typedef struct {
    float4 position [[position]];
    float4 currentClipPos;
    float4 previousClipPos;
} VelocityVertexData;

vertex VelocityVertexData velocityVertex(
    Vertex in [[stage_in]],
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
    VelocityVertexData out;

#if INSTANCING
    const float4x4 modelMatrix = instanceUniforms[instanceID].modelMatrix;
    out.currentClipPos = vertexUniforms[amp_id].viewProjectionMatrix * modelMatrix * float4(in.position, 1.0);
    out.previousClipPos = vertexUniforms[amp_id].previousViewProjectionMatrix * modelMatrix * float4(in.position, 1.0);
#else
    out.currentClipPos = vertexUniforms[amp_id].modelViewProjectionMatrix * float4(in.position, 1.0);
    out.previousClipPos = vertexUniforms[amp_id].previousModelViewProjectionMatrix * float4(in.position, 1.0);
#endif

    out.position = out.currentClipPos;
    return out;
}

fragment half2 velocityFragment(VelocityVertexData in [[stage_in]]) {
    const float2 current = in.currentClipPos.xy / in.currentClipPos.w;
    const float2 previous = in.previousClipPos.xy / in.previousClipPos.w;
    const float2 delta = current - previous;
    // Convert NDC delta (+Y up) to UV delta (+V down) so consumers read screen-space velocity directly.
    return half2(delta.x, -delta.y);
}
