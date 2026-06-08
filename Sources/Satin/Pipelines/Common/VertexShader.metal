vertex VertexData satinVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
    VertexData out;

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix *
                   instanceUniforms[instanceID].modelMatrix * float4(in.position, 1.0);

#if HAS_NORMAL
    out.normal = instanceUniforms[instanceID].normalMatrix * in.normal;
#endif

#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * float4(in.position, 1.0);

#if HAS_NORMAL
    out.normal = vertexUniforms[amp_id].normalMatrix * in.normal;
#endif

#endif

#if HAS_TEXCOORD
    out.texcoord = in.texcoord;
#endif

    return out;
}
