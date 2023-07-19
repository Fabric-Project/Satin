#include "Library/Colors.metal"

typedef struct {
    float time;
} RainbowUniforms;

typedef struct {
    float4 position [[position]];
    float id;
} CustomVertexData;

vertex CustomVertexData rainbowVertex
(
    Vertex in [[stage_in]],
    // inject instancing args
    constant VertexUniforms &vertexUniforms [[buffer(VertexBufferVertexUniforms)]]
)
{
    const float4 position = float4(in.position.xyz, 1.0);

    CustomVertexData out;
#if INSTANCING
    out.position = vertexUniforms.viewProjectionMatrix * instanceUniforms[instanceID].modelMatrix * position;
#else
    out.position = vertexUniforms.modelViewProjectionMatrix * position;
#endif
    out.id = float(instanceID);
    return out;
}

fragment float4 rainbowFragment
(
    CustomVertexData in [[stage_in]],
    constant RainbowUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]]
)
{
    const float uv = in.id/1000.0 + uniforms.time * 0.5;
    return float4(iridescence(uv), 1.0);
}
