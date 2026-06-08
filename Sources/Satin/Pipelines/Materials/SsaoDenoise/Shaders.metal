#include "Library/Pi.metal"
#include "Library/ScreenSpace/ScreenSpaceUtilities.metal"

typedef struct {
    float4x4 inverseProjectionMatrix;
    float4x4 viewMatrix;
    float radius;
    float depthPhi;
    float normalPhi;
    float _padding;
} SsaoDenoiseUniforms;

constant float3 ssaoPoissonDisk[16] = {
    float3( 1.000000000,  0.000000000, 0.000000000),
    float3( 0.707106781,  0.707106781, 0.066666667),
    float3( 0.000000000,  1.000000000, 0.133333333),
    float3(-0.707106781,  0.707106781, 0.200000000),
    float3(-1.000000000,  0.000000000, 0.266666667),
    float3(-0.707106781, -0.707106781, 0.333333333),
    float3( 0.000000000, -1.000000000, 0.400000000),
    float3( 0.707106781, -0.707106781, 0.466666667),
    float3( 1.000000000,  0.000000000, 0.533333333),
    float3( 0.707106781,  0.707106781, 0.600000000),
    float3( 0.000000000,  1.000000000, 0.666666667),
    float3(-0.707106781,  0.707106781, 0.733333333),
    float3(-1.000000000,  0.000000000, 0.800000000),
    float3(-0.707106781, -0.707106781, 0.866666667),
    float3( 0.000000000, -1.000000000, 0.933333333),
    float3( 0.707106781, -0.707106781, 1.000000000)
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

fragment half ssaoDenoiseFragment(
    VertexData in [[stage_in]],
    constant SsaoDenoiseUniforms &uniforms [[buffer(FragmentBufferCustom0)]],
    texture2d<half, access::sample> aoTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> linearDepthTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom2)]],
    texture2d<float, access::sample> noiseTex [[texture(FragmentTextureCustom3)]]
) {
    constexpr sampler aoSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler depthSampler(filter::nearest, address::clamp_to_edge);
    constexpr sampler normalSampler(filter::nearest, address::clamp_to_edge);
    constexpr sampler noiseSampler(filter::nearest, address::repeat);

    const float2 uv = in.texcoord;
    const half centerAO = aoTex.sample(aoSampler, uv).r;
    const float centerDepth = linearDepthTex.sample(depthSampler, uv).r;
    if (centerDepth <= 0.0) {
        return 1.0h;
    }

    float3 centerNormal = satinDecodeViewNormal(normalTex.sample(normalSampler, uv).xyz, uniforms.viewMatrix);
    if (dot(centerNormal, centerNormal) <= 1.0e-5) {
        return centerAO;
    }
    centerNormal = normalize(centerNormal);

    const float3 centerViewPosition = satinReconstructLinearViewPosition(
        uv,
        centerDepth,
        uniforms.inverseProjectionMatrix
    );

    const float2 resolution = float2(aoTex.get_width(), aoTex.get_height());
    const float2 noiseResolution = max(float2(noiseTex.get_width(), noiseTex.get_height()), 1.0);
    const float2 noiseUV = uv * (resolution / noiseResolution);
    const float noiseAngle = noiseTex.sample(noiseSampler, noiseUV).r * (2.0 * PI);
    const float sinAngle = sin(noiseAngle);
    const float cosAngle = cos(noiseAngle);
    const float2x2 rotationMatrix = float2x2(
        float2(cosAngle, sinAngle),
        float2(-sinAngle, cosAngle)
    );

    half totalAO = centerAO;
    float totalWeight = 1.0;
    const float safeDepthPhi = max(uniforms.depthPhi, 1.0e-4);
    const float safeNormalPhi = max(uniforms.normalPhi, 1.0e-4);

    for (int i = 0; i < 16; ++i) {
        const float3 sampleDir = ssaoPoissonDisk[i];
        const float2 offset = rotationMatrix * (
            sampleDir.xy * (1.0 + sampleDir.z * max(uniforms.radius - 1.0, 0.0)) / resolution
        );
        const float2 sampleUV = uv + offset;
        if (!satinUvInside(sampleUV)) {
            continue;
        }

        const float sampleDepth = linearDepthTex.sample(depthSampler, sampleUV).r;
        if (sampleDepth <= 0.0) {
            continue;
        }

        float3 sampleNormal = satinDecodeViewNormal(normalTex.sample(normalSampler, sampleUV).xyz, uniforms.viewMatrix);
        if (dot(sampleNormal, sampleNormal) <= 1.0e-5) {
            continue;
        }
        sampleNormal = normalize(sampleNormal);

        const float3 sampleViewPosition = satinReconstructLinearViewPosition(
            sampleUV,
            sampleDepth,
            uniforms.inverseProjectionMatrix
        );
        const float normalWeight = pow(max(dot(centerNormal, sampleNormal), 0.0), safeNormalPhi);
        const float depthDifference = abs(dot(centerViewPosition - sampleViewPosition, centerNormal));
        const float depthWeight = max(1.0 - depthDifference / safeDepthPhi, 0.0);
        const float spatialWeight = 1.0 - sampleDir.z * 0.35;
        const float weight = normalWeight * depthWeight * spatialWeight;

        if (weight <= 1.0e-4) {
            continue;
        }

        totalAO += aoTex.sample(aoSampler, sampleUV).r * half(weight);
        totalWeight += weight;
    }

    return totalAO / half(totalWeight);
}
