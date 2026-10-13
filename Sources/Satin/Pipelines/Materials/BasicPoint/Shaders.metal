#include "../../Library/Shapes/Circle.metal"

typedef struct {
    float4 color; // color
    float size;
    float sizeHalf;
} BasicPointUniforms;

typedef struct {
    float4 position [[position]];
    float pointSize [[point_size]];
} BasicPointCustomVertexData;

vertex BasicPointCustomVertexData basicPointVertex(
    Vertex in [[stage_in]],
    ushort amp_id [[amplification_id]],
    // inject instancing args
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant BasicPointUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {

    const float4 position = SATIN_SKIN_POSITION(in);

    BasicPointCustomVertexData out;
#if INSTANCING
    const float4x4 modelMatrix = instanceUniforms[instanceID].modelMatrix;
    out.position = vertexUniforms[amp_id].viewProjectionMatrix * modelMatrix * position;
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * position;
#endif
    out.pointSize = uniforms.size + 1.0;
    return out;
}

struct FragOut {
    float4 color [[color(0)]];
    float depth [[depth(any)]];
};

fragment FragOut basicPointFragment(
    BasicPointCustomVertexData in [[stage_in]],
    const float2 puv [[point_coord]],
    constant BasicPointUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
    const float size = uniforms.size;
    const float sizeHalf = uniforms.sizeHalf;

    const float2 uv = size * puv - sizeHalf;
    float result = length(uv);
    result = smoothstep(sizeHalf, sizeHalf - 1.0, result);

    FragOut out;
    out.color = float4(uniforms.color.rgb, uniforms.color.a * result);
    out.depth = mix(0.0, in.position.z, result);
    return out;
}
