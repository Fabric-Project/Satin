#include "Library/Halton.metal"

typedef struct {
    float4x4 projectionMatrix;
    float4x4 inverseProjectionMatrix;
    float4x4 viewMatrix;
    float radius;
    float bias;
    int kernelSize;
} SsaoUniforms;

static constant float3 ssaoKernel[] = {
    float3( 0.0490, 0.0000,  0.0490),
    float3(-0.0520, 0.0000,  0.1040),
    float3( 0.0225, 0.0225,  0.0637),
    float3(-0.1414, 0.0000,  0.1414),
    float3( 0.1936, 0.0000,  0.0968),
    float3(-0.0612, 0.0612,  0.1224),
    float3( 0.2828, 0.0000,  0.0000),
    float3(-0.1875, 0.1875,  0.1875),
    float3( 0.0750, 0.0750,  0.2250),
    float3(-0.1677, 0.0000,  0.3354),
    float3( 0.3900, 0.0000,  0.1300),
    float3(-0.2449, 0.2449,  0.2449),
    float3( 0.0888, 0.1776,  0.3552),
    float3(-0.4330, 0.0000,  0.2500),
    float3( 0.5000, 0.0000,  0.0000),
    float3(-0.3536, 0.3536,  0.0000),
};

static float3 ssaoReconstructViewPos(float2 uv, float depth, float4x4 invProj) {
    const float4 clipPos = float4(uv * 2.0 - 1.0, depth, 1.0);
    float4 viewPos = invProj * clipPos;
    return viewPos.xyz / viewPos.w;
}

fragment half ssaoFragment(
    VertexData in [[stage_in]],
    constant SsaoUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom1)]]) {

    constexpr sampler s(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;

    const float depth = depthTex.sample(s, uv);
    if (depth >= 1.0) return 1.0h;

    const float3 fragViewPos = ssaoReconstructViewPos(uv, depth, uniforms.inverseProjectionMatrix);

    // NormalColorMaterial stores world-space normals; transform to view space
    const float3 worldNormal = normalTex.sample(s, uv).xyz;
    const float3 normal = normalize((uniforms.viewMatrix * float4(worldNormal, 0.0)).xyz);

    const float3 randomVec = normalize(float3(
        halton(uint(in.position.x) * 1973u + uint(in.position.y) * 9277u, 0) * 2.0 - 1.0,
        halton(uint(in.position.x) * 9277u + uint(in.position.y) * 1973u, 1) * 2.0 - 1.0,
        0.0));

    const float3 tangent = normalize(randomVec - normal * dot(randomVec, normal));
    const float3 bitangent = cross(normal, tangent);
    const float3x3 TBN = float3x3(tangent, bitangent, normal);

    const int kernelSize = clamp(uniforms.kernelSize, 1, 16);
    const float radius = uniforms.radius;
    const float bias = uniforms.bias;

    float occlusion = 0.0;
    for (int i = 0; i < kernelSize; i++) {
        float3 samplePos = fragViewPos + TBN * ssaoKernel[i] * radius;

        float4 offset = uniforms.projectionMatrix * float4(samplePos, 1.0);
        offset.xyz /= offset.w;
        const float2 sampleUV = offset.xy * 0.5 + 0.5;

        const float sampleDepth = depthTex.sample(s, sampleUV);
        const float3 sampleViewPos = ssaoReconstructViewPos(sampleUV, sampleDepth, uniforms.inverseProjectionMatrix);

        const float rangeCheck = smoothstep(0.0, 1.0, radius / abs(fragViewPos.z - sampleViewPos.z + 1e-5));
        occlusion += (sampleViewPos.z >= samplePos.z + bias ? 1.0 : 0.0) * rangeCheck;
    }

    return half(1.0 - occlusion / float(kernelSize));
}
