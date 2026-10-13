vertex float4 satinShadowVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    constant VertexUniforms &vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
    const float4 position = SATIN_SKIN_POSITION(in);
#if INSTANCING
    return vertexUniforms.viewProjectionMatrix * instanceUniforms[instanceID].modelMatrix *
           position;
#else
    return vertexUniforms.modelViewProjectionMatrix * position;
#endif
}
