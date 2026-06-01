#include "Library/ScreenSpace/ScreenSpaceUtilities.metal"

typedef struct {
    float4x4 inverseProjectionMatrix;
    float4x4 viewMatrix;
    // World/view-space depth tolerance along the center normal.
    float depthPhi;    // slider,0.01,2.0,0.1, Depth Phi
    // Normal similarity exponent used to preserve silhouettes and contacts.
    float normalPhi;   // slider,0.1,32.0,8.0, Normal Phi
    // kernel half-size in pixels; 0 = pass-through
    int blurRadius;    // slider,0,4,4, Blur Radius
} SsaoBlurUniforms;

typedef struct {
    float2 direction;
} SsaoBlurPassUniforms;

fragment half ssaoBlurFragment(
    VertexData in [[stage_in]],
    constant SsaoBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    constant SsaoBlurPassUniforms &passUniforms [[buffer(FragmentBufferCustom0)]],
    texture2d<half, access::sample> ssaoTex  [[texture(FragmentTextureCustom0)]],
    depth2d<float, access::sample> depthTex  [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom2)]]
) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    const float2 uv = in.texcoord;

    const float centerDepth = depthTex.sample(s, uv);
    // Reversed-Z: background cleared to 0.0 — no AO needed.
    if (centerDepth <= 0.0) return 1.0h;

    float3 centerNormal = satinDecodeViewNormal(normalTex.sample(s, uv).xyz, uniforms.viewMatrix);
    if (dot(centerNormal, centerNormal) <= 1.0e-5) {
        return ssaoTex.sample(s, uv).r;
    }
    centerNormal = normalize(centerNormal);

    const float3 centerViewPosition = satinReconstructViewPosition(
        uv,
        centerDepth,
        uniforms.inverseProjectionMatrix
    );

    const int radius = clamp(uniforms.blurRadius, 0, 4);
    if (radius == 0) return ssaoTex.sample(s, uv).r;

    const float2 texelSize = float2(
        1.0 / float(ssaoTex.get_width()),
        1.0 / float(ssaoTex.get_height())
    );
    const float2 sampleStep = passUniforms.direction * texelSize;

    half  totalAO     = 0.0h;
    float totalWeight = 0.0;
    const float safeDepthPhi = max(uniforms.depthPhi, 1.0e-4);
    const float safeNormalPhi = max(uniforms.normalPhi, 1.0e-4);

    for (int i = -radius; i <= radius; i++) {
        const float2 sampleUV = uv + sampleStep * float(i);
        if (!satinUvInside(sampleUV)) {
            continue;
        }

        const float sampleDepth = depthTex.sample(s, sampleUV);
        if (sampleDepth <= 0.0) {
            continue;
        }

        float3 sampleNormal = satinDecodeViewNormal(normalTex.sample(s, sampleUV).xyz, uniforms.viewMatrix);
        if (dot(sampleNormal, sampleNormal) <= 1.0e-5) {
            continue;
        }
        sampleNormal = normalize(sampleNormal);

        const float3 sampleViewPosition = satinReconstructViewPosition(
            sampleUV,
            sampleDepth,
            uniforms.inverseProjectionMatrix
        );
        const float depthDifference = abs(dot(centerViewPosition - sampleViewPosition, centerNormal));
        const float depthWeight = max(1.0 - depthDifference / safeDepthPhi, 0.0);
        const float normalWeight = pow(max(dot(centerNormal, sampleNormal), 0.0), safeNormalPhi);
        const float weight = depthWeight * normalWeight;

        if (weight <= 1.0e-4) {
            continue;
        }

        totalAO += ssaoTex.sample(s, sampleUV).r * half(weight);
        totalWeight += weight;
    }

    return (totalWeight > 0.0) ? (totalAO / half(totalWeight)) : 1.0h;
}
