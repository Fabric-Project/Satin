vertex VertexData satinVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
    VertexData out;

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix *
                   instanceUniforms[instanceID].modelMatrix * SATIN_SKIN_POSITION(in);

#if HAS_NORMAL
    out.normal = instanceUniforms[instanceID].normalMatrix * SATIN_SKIN_NORMAL(in);
#endif

#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * SATIN_SKIN_POSITION(in);

#if HAS_NORMAL
    out.normal = vertexUniforms[amp_id].normalMatrix * SATIN_SKIN_NORMAL(in);
#endif

#endif

#if HAS_TEXCOORD
    out.texcoord = in.texcoord;
#endif

    return out;
}
