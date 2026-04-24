#include "Library/Luminance.metal"
#include "Library/Pi.metal"
#include "Library/ScreenSpace/ScreenSpaceUtilities.metal"

typedef struct {
    float4x4 inverseProjectionMatrix;
    float4x4 viewMatrix;
    float radius;      // slider,1.0,16.0,5.0
    float lumaPhi;     // slider,0.1,20.0,5.0
    float depthPhi;    // slider,0.1,20.0,5.0
    float normalPhi;   // slider,0.1,64.0,5.0
    int noiseIndex;
} SsgiBlurUniforms;

// Direct port of three.js PoissonDenoiseShader's generated sample kernel:
// generatePdSamplePointInitializer( 16, 2, 1 )
constant float3 ssgiPoissonDisk[16] = {
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

fragment float4 ssgiBlurFragment(
    VertexData in [[stage_in]],
    constant SsgiBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> ssgiTex [[texture(FragmentTextureCustom0)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom2)]],
    texture2d<float, access::sample> noiseTex [[texture(FragmentTextureCustom3)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);
    constexpr sampler noiseSampler(filter::nearest, address::repeat);

    const float2 uv = in.texcoord;
    const float4 centerTexel = ssgiTex.sample(linearSampler, uv);
    const float centerDepth = depthTex.sample(nearestSampler, uv);
    if (centerDepth <= 0.0) {
        return centerTexel;
    }

    float3 centerNormal = satinDecodeViewNormal(normalTex.sample(nearestSampler, uv).xyz, uniforms.viewMatrix);
    if (dot(centerNormal, centerNormal) <= 1.0e-5) {
        return centerTexel;
    }
    centerNormal = normalize(centerNormal);

    const float3 centerViewPosition = satinReconstructViewPosition(uv, centerDepth, uniforms.inverseProjectionMatrix);
    const float2 resolution = float2(ssgiTex.get_width(), ssgiTex.get_height());
    const float clampedRadius = clamp(uniforms.radius, 1.0, 16.0);

    const float2 noiseResolution = max(float2(noiseTex.get_width(), noiseTex.get_height()), 1.0);
    const float2 noiseUV = uv * (resolution / noiseResolution);
    const float4 noiseTexel = noiseTex.sample(noiseSampler, noiseUV);
    const int channel = int(uint(uniforms.noiseIndex) & 3u);
    const float noiseAngle = noiseTexel[channel] * (2.0 * PI);
    const float sinAngle = sin(noiseAngle);
    const float cosAngle = cos(noiseAngle);

    float4 denoised = centerTexel;
    float totalWeight = 1.0;
    const float safeLumaPhi = max(uniforms.lumaPhi, 1.0e-4);
    const float safeDepthPhi = max(uniforms.depthPhi, 1.0e-4);
    const float safeNormalPhi = max(uniforms.normalPhi, 1.0e-4);
    const float2x2 rotationMatrix = float2x2(
        float2(cosAngle, sinAngle),
        float2(-sinAngle, cosAngle)
    );

    for (int i = 0; i < 16; i++) {
        const float3 sampleDir = ssgiPoissonDisk[i];
        const float2 offset = rotationMatrix * (
            sampleDir.xy * (1.0 + sampleDir.z * (clampedRadius - 1.0)) / resolution
        );
        const float2 sampleUV = uv + offset;

        if (!satinUvInside(sampleUV)) {
            continue;
        }

        const float sampleDepth = depthTex.sample(nearestSampler, sampleUV);
        if (sampleDepth <= 0.0) {
            continue;
        }

        const float4 sampleTexel = ssgiTex.sample(linearSampler, sampleUV);
        float3 sampleNormal = satinDecodeViewNormal(normalTex.sample(nearestSampler, sampleUV).xyz, uniforms.viewMatrix);
        if (dot(sampleNormal, sampleNormal) <= 1.0e-5) {
            continue;
        }
        sampleNormal = normalize(sampleNormal);

        const float3 sampleViewPosition = satinReconstructViewPosition(
            sampleUV,
            sampleDepth,
            uniforms.inverseProjectionMatrix
        );

        const float normalSimilarity = pow(max(dot(centerNormal, sampleNormal), 0.0), safeNormalPhi);
        const float lumaDifference = abs(luminance(sampleTexel.rgb) - luminance(centerTexel.rgb));
        const float lumaSimilarity = max(1.0 - lumaDifference / safeLumaPhi, 0.0);
        const float depthDifference = abs(dot(centerViewPosition - sampleViewPosition, centerNormal));
        const float depthSimilarity = max(1.0 - depthDifference / safeDepthPhi, 0.0);
        const float weight = lumaSimilarity * depthSimilarity * normalSimilarity;

        if (weight <= 1.0e-4) {
            continue;
        }

        denoised += sampleTexel * weight;
        totalWeight += weight;
    }

    return denoised / totalWeight;
}
