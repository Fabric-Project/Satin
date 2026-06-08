#include "../../Library/Map.metal"
#include "../../Library/Colors.metal"
#include "../../Library/Dither.metal"

typedef struct {
    float4 position [[position]];
    float depth;
    float pointSize [[point_size]];
} DepthVertexData;

typedef struct {
    float near;      // input
    float far;       // input
    bool invert;     // toggle
    bool color;      // toggle
    float pointSize; // slider,1.0,64.0,1.0
} DepthUniforms;

vertex DepthVertexData depthVertex(
    Vertex v [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant DepthUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {
#if INSTANCING
    const float4 position = vertexUniforms[amp_id].viewMatrix *
                            instanceUniforms[instanceID].modelMatrix * float4(v.position, 1.0);
#else
    const float4 position = vertexUniforms[amp_id].modelViewMatrix * float4(v.position, 1.0);
#endif
    const float z = position.z;

    const float4x4 projection = vertexUniforms[amp_id].projectionMatrix;
    const float c = projection[2].z;
    const float d = projection[3].z;

    const float n = d / c;
    const float f = d / (1.0 + c);

    float near = uniforms.near;
    float far = uniforms.far;

    near = mix(n, near, saturate(sign(near)));
    far = mix(f, far, saturate(sign(far)));

    const float depth = map(-z, near, far, 1.0, 0.0);
    DepthVertexData out;
    out.position = projection * position;
    out.depth = depth;
    out.pointSize = uniforms.pointSize;
    return out;
}

fragment float4 depthFragment(
    DepthVertexData in [[stage_in]],
    constant DepthUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
    const float depth = uniforms.invert ? 1.0 - in.depth : in.depth;
    float3 color = mix(float3(depth), turbo(depth), uniforms.color);
    color = dither8x8(in.position.xy, color);
    return float4(color, 1.0);
}
