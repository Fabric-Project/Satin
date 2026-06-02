#include "Library/ScreenSpace/ScreenSpaceUtilities.metal"

typedef struct {
    float4x4 projectionMatrix;
    float4x4 inverseProjectionMatrix;
    float4x4 viewMatrix;
    float radius;
    float bias;
    int sampleCount;
    int _padding;
} SsaoUniforms;

static constant float3 ssaoKernel[16] = {
    float3( 0.0308,  0.0000,  0.0308),
    float3(-0.0655,  0.0000,  0.0655),
    float3( 0.0414,  0.0414,  0.0828),
    float3(-0.1237,  0.0000,  0.1237),
    float3( 0.1615,  0.0000,  0.0808),
    float3(-0.0742,  0.0742,  0.1485),
    float3( 0.2121,  0.0000,  0.2121),
    float3(-0.1875,  0.1875,  0.1875),
    float3( 0.1061,  0.1061,  0.3182),
    float3(-0.2357,  0.0000,  0.2357),
    float3( 0.3250,  0.0000,  0.1625),
    float3(-0.2449,  0.2449,  0.2449),
    float3( 0.1155,  0.2309,  0.4619),
    float3(-0.3248,  0.0000,  0.3248),
    float3( 0.3536,  0.0000,  0.3536),
    float3(-0.3464,  0.3464,  0.1000),
};

static float3 satinViewRayFromUv(float2 uv, float4x4 inverseProjectionMatrix) {
    const float3 ray = satinReconstructViewPosition(uv, 1.0, inverseProjectionMatrix);
    return ray / max(-ray.z, 1.0e-6);
}

static float3 satinReconstructLinearViewPosition(
    float2 uv,
    float linearDepth,
    float4x4 inverseProjectionMatrix
) {
    return satinViewRayFromUv(uv, inverseProjectionMatrix) * linearDepth;
}

fragment half ssaoFragment(
    VertexData in [[stage_in]],
    constant SsaoUniforms &uniforms [[buffer(FragmentBufferCustom0)]],
    texture2d<float, access::sample> linearDepthTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> noiseTex [[texture(FragmentTextureCustom2)]]
) {
    constexpr sampler depthSampler(filter::nearest, address::clamp_to_edge);
    constexpr sampler normalSampler(filter::nearest, address::clamp_to_edge);
    constexpr sampler noiseSampler(filter::nearest, address::repeat);

    const float2 uv = in.texcoord;
    const float linearDepth = linearDepthTex.sample(depthSampler, uv).r;
    if (linearDepth <= 0.0) {
        return 1.0h;
    }

    float3 normal = satinDecodeViewNormal(normalTex.sample(normalSampler, uv).xyz, uniforms.viewMatrix);
    if (dot(normal, normal) <= 1.0e-5) {
        return 1.0h;
    }
    normal = normalize(normal);

    const float3 fragViewPos = satinReconstructLinearViewPosition(
        uv,
        linearDepth,
        uniforms.inverseProjectionMatrix
    );

    const float2 resolution = float2(linearDepthTex.get_width(), linearDepthTex.get_height());
    const float2 noiseResolution = max(float2(noiseTex.get_width(), noiseTex.get_height()), 1.0);
    const float2 noiseUV = uv * (resolution / noiseResolution);
    float3 randomVec = noiseTex.sample(noiseSampler, noiseUV).xyz * 2.0 - 1.0;
    randomVec.z = 0.0;
    if (dot(randomVec.xy, randomVec.xy) <= 1.0e-5) {
        randomVec = float3(0.70710678, 0.70710678, 0.0);
    } else {
        randomVec = normalize(randomVec);
    }

    float3 tangent = randomVec - normal * dot(randomVec, normal);
    if (dot(tangent, tangent) <= 1.0e-5) {
        tangent = abs(normal.z) < 0.999 ? normalize(cross(normal, float3(0.0, 0.0, 1.0))) : float3(1.0, 0.0, 0.0);
    } else {
        tangent = normalize(tangent);
    }
    const float3 bitangent = normalize(cross(normal, tangent));
    const float3x3 tbn = float3x3(tangent, bitangent, normal);

    const int sampleCount = clamp(uniforms.sampleCount, 1, 16);
    float occlusion = 0.0;

    for (int i = 0; i < sampleCount; ++i) {
        const float3 sampleViewPos = fragViewPos + (tbn * ssaoKernel[i]) * uniforms.radius;
        const float2 sampleUV = satinProjectViewPositionToUv(sampleViewPos, uniforms.projectionMatrix);
        if (!satinUvInside(sampleUV)) {
            continue;
        }

        const float sampleLinearDepth = linearDepthTex.sample(depthSampler, sampleUV).r;
        if (sampleLinearDepth <= 0.0) {
            continue;
        }

        const float3 sampleSurfacePos = satinReconstructLinearViewPosition(
            sampleUV,
            sampleLinearDepth,
            uniforms.inverseProjectionMatrix
        );
        const float rangeWeight = smoothstep(0.0, 1.0, uniforms.radius / max(abs(linearDepth - sampleLinearDepth), 1.0e-4));
        occlusion += (sampleSurfacePos.z >= sampleViewPos.z + uniforms.bias ? 1.0 : 0.0) * rangeWeight;
    }

    const float ao = pow(saturate(1.0 - occlusion / float(sampleCount)), 1.5);
    return half(ao);
}
