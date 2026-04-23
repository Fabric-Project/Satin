#include "Library/Luminance.metal"
#include "Library/Pi.metal"
#include "Library/Random.metal"
#include "Library/ScreenSpace/ScreenSpaceUtilities.metal"

typedef struct {
    float4x4 projectionMatrix;
    float4x4 inverseProjectionMatrix;
    float4x4 viewMatrix;
    float radius;              // slider,0.25,48.0,12.0
    float thickness;           // slider,0.05,6.0,1.0
    float expFactor;           // slider,1.0,4.0,2.0
    float jitterStrength;      // slider,0.0,1.0,1.0
    float halfProjectionScale;
    int sliceCount;            // slider,1,6,3
    int stepCount;             // slider,1,16,8
} SsgiUniforms;

fragment float4 ssgiFragment(
    VertexData in [[stage_in]],
    constant SsgiUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom2)]],
    texture2d<float, access::sample> albedoTex [[texture(FragmentTextureCustom3)]],
    texture2d<float, access::sample> pbrTex [[texture(FragmentTextureCustom4)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float depth = depthTex.sample(nearestSampler, uv);
    if (depth <= 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    const float3 viewPosition = satinReconstructViewPosition(uv, depth, uniforms.inverseProjectionMatrix);
    float3 viewNormal = satinDecodeViewNormal(normalTex.sample(nearestSampler, uv).xyz, uniforms.viewMatrix);
    if (dot(viewNormal, viewNormal) <= 1.0e-5) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    viewNormal = normalize(viewNormal);

    const float3 receiverAlbedo = albedoTex.sample(linearSampler, uv).rgb;
    const float4 receiverPbr = pbrTex.sample(nearestSampler, uv);
    const float receiverMetallic = receiverPbr.g;
    const float3 receiverDiffuse = receiverAlbedo * (1.0 - receiverMetallic);

    const int slices = clamp(uniforms.sliceCount, 1, 4);
    const int steps = clamp(uniforms.stepCount, 1, 32);
    const float2 texelSize = 1.0 / float2(colorTex.get_width(), colorTex.get_height());
    const float projectedRadius = max(
        uniforms.radius * uniforms.halfProjectionScale / max(-viewPosition.z, 1.0e-3),
        1.0
    );
    const float angularNoise = random(float2(in.position.xy));
    const float radialNoise = random(float2(in.position.xy) + float2(19.19, 73.17));
    const float jitterStrength = clamp(uniforms.jitterStrength, 0.0, 1.0);

    float3 indirect = 0.0;
    float occlusion = 0.0;
    float indirectWeightSum = 0.0;
    float occlusionWeightSum = 0.0;

    for (int slice = 0; slice < slices; slice++) {
        const float angleJitter = fract(angularNoise + float(slice) * 0.61803398875);
        const float angle = (float(slice) + angleJitter) * PI / float(slices);
        const float2 axis = float2(cos(angle), sin(angle));

        for (int side = -1; side <= 1; side += 2) {
            const float2 direction = axis * float(side);
            const float intervalNoise = fract(
                radialNoise
                    + float(slice) * 0.754877666
                    + (side < 0 ? 0.245122334 : 0.745122334)
            );
            const float stepOffset = mix(0.5, intervalNoise, jitterStrength);

            for (int step = 0; step < steps; step++) {
                const float stepFraction = clamp(
                    (float(step) + stepOffset) / float(steps),
                    1.0e-3,
                    1.0
                );
                const float stepAlpha = pow(stepFraction, uniforms.expFactor);
                const float pixelOffset = max(projectedRadius * stepAlpha, 1.0);
                const float2 sampleUV = uv + direction * texelSize * pixelOffset;

                if (!satinUvInside(sampleUV)) {
                    break;
                }

                const float sampleDepth = depthTex.sample(nearestSampler, sampleUV);
                if (sampleDepth <= 0.0) {
                    continue;
                }

                const float3 sampleViewPosition = satinReconstructViewPosition(
                    sampleUV,
                    sampleDepth,
                    uniforms.inverseProjectionMatrix
                );

                const float3 delta = sampleViewPosition - viewPosition;
                const float distanceToSample = length(delta);
                if (distanceToSample <= 1.0e-4 || distanceToSample > uniforms.radius) {
                    continue;
                }

                const float3 lightDirection = delta / distanceToSample;
                const float receiverWeight = saturate(dot(viewNormal, lightDirection));
                if (receiverWeight <= 1.0e-3) {
                    continue;
                }

                const float depthDelta = abs(sampleViewPosition.z - viewPosition.z);
                const float thicknessWeight = saturate(1.0 - depthDelta / max(uniforms.thickness, 1.0e-3));
                if (thicknessWeight <= 1.0e-3) {
                    continue;
                }

                float3 sampleViewNormal = satinDecodeViewNormal(
                    normalTex.sample(nearestSampler, sampleUV).xyz,
                    uniforms.viewMatrix
                );
                if (dot(sampleViewNormal, sampleViewNormal) <= 1.0e-5) {
                    continue;
                }
                sampleViewNormal = normalize(sampleViewNormal);

                const float emitterWeight = saturate(dot(sampleViewNormal, -lightDirection));
                if (emitterWeight <= 1.0e-3) {
                    continue;
                }

                const float4 samplePbr = pbrTex.sample(nearestSampler, sampleUV);
                const float sourceBounce = 1.0 - samplePbr.g;
                const float distanceWeight = saturate(1.0 - distanceToSample / uniforms.radius);
                const float attenuation = distanceWeight * distanceWeight;
                const float visibilityWeight = receiverWeight * attenuation;
                const float sampleWeight = visibilityWeight * emitterWeight * thicknessWeight * sourceBounce;

                if (sampleWeight <= 1.0e-4) {
                    continue;
                }

                indirect += colorTex.sample(linearSampler, sampleUV).rgb * sampleWeight;
                indirectWeightSum += sampleWeight;
                occlusion += visibilityWeight * thicknessWeight;
                occlusionWeightSum += visibilityWeight;
            }
        }
    }

    if (indirectWeightSum <= 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    indirect = (indirect / indirectWeightSum) * receiverDiffuse;

    const float indirectLuminance = luminance(indirect);
    if (indirectLuminance > 8.0) {
        indirect *= 8.0 / indirectLuminance;
    }

    const float visibility = occlusionWeightSum > 0.0
        ? saturate(1.0 - occlusion / occlusionWeightSum)
        : 1.0;
    return float4(max(indirect, 0.0), visibility);
}
