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

static float3 ssgiDenoiseViewNormal(
    texture2d<float, access::sample> normalTex,
    sampler nearestSampler,
    float2 uv,
    float4x4 viewMatrix
) {
    return normalize(satinDecodeViewNormal(normalTex.sample(nearestSampler, uv).xyz, viewMatrix));
}

fragment float4 ssgiBlurFragment(
    VertexData in [[stage_in]],
    constant SsgiBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> ssgiTex [[texture(FragmentTextureCustom0)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom2)]],
    texture2d<float, access::read> noiseTex [[texture(FragmentTextureCustom3)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

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

    uint2 noiseCoord = uint2(in.position.xy);
    if (noiseTex.get_width() > 0 && noiseTex.get_height() > 0) {
        noiseCoord.x %= uint(noiseTex.get_width());
        noiseCoord.y %= uint(noiseTex.get_height());
    }
    const float4 noiseTexel = noiseTex.read(noiseCoord);
    const int channel = clamp(uniforms.noiseIndex, 0, 3);
    const float noiseAngle = noiseTexel[channel] * (2.0 * PI);
    const float sinAngle = sin(noiseAngle);
    const float cosAngle = cos(noiseAngle);

    float4 denoised = centerTexel;
    float totalWeight = 1.0;
    const float safeLumaPhi = max(uniforms.lumaPhi, 1.0e-4);
    const float safeDepthPhi = max(uniforms.depthPhi, 1.0e-4);
    const float safeNormalPhi = max(uniforms.normalPhi, 1.0e-4);

    for (int i = 0; i < 16; i++) {
        const float sampleAngle = 2.0 * PI * 2.0 * float(i) / 16.0;
        const float ringRadius = float(i) / 15.0;
        const float2 sampleDirection = float2(cos(sampleAngle), sin(sampleAngle));
        const float2 rotatedDirection = float2(
            cosAngle * sampleDirection.x - sinAngle * sampleDirection.y,
            sinAngle * sampleDirection.x + cosAngle * sampleDirection.y
        );
        const float sampleRadius = 1.0 + ringRadius * (clampedRadius - 1.0);
        const float2 sampleUV = uv + rotatedDirection * (sampleRadius / resolution);

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
