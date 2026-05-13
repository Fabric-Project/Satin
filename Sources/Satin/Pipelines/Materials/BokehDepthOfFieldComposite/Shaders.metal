typedef struct {
    float maxRadius;
    float blend;
} BokehDepthOfFieldCompositeUniforms;

constant int kBokehCompositeKernelRadius = 8;
constant int kBokehCompositeKernelCount = 17;
constant float kBokehCompositeCoCActivationThreshold = 1.0e-3f;

static constant float4 kCompositeFarKernel0[kBokehCompositeKernelCount] = {
    float4(0.014096f, -0.022658f, 0.055991f, 0.004413f),
    float4(-0.020612f, -0.025574f, 0.019188f, 0.000000f),
    float4(-0.038708f, 0.006957f, 0.000000f, 0.049223f),
    float4(-0.021449f, 0.040468f, 0.018301f, 0.099929f),
    float4(0.013015f, 0.050223f, 0.054845f, 0.114689f),
    float4(0.042178f, 0.038585f, 0.085769f, 0.097080f),
    float4(0.057972f, 0.019812f, 0.102517f, 0.068674f),
    float4(0.063647f, 0.005252f, 0.108535f, 0.046643f),
    float4(0.064754f, 0.000000f, 0.109709f, 0.038697f),
    float4(0.063647f, 0.005252f, 0.108535f, 0.046643f),
    float4(0.057972f, 0.019812f, 0.102517f, 0.068674f),
    float4(0.042178f, 0.038585f, 0.085769f, 0.097080f),
    float4(0.013015f, 0.050223f, 0.054845f, 0.114689f),
    float4(-0.021449f, 0.040468f, 0.018301f, 0.099929f),
    float4(-0.038708f, 0.006957f, 0.000000f, 0.049223f),
    float4(-0.020612f, -0.025574f, 0.019188f, 0.000000f),
    float4(0.014096f, -0.022658f, 0.055991f, 0.004413f)
};

static constant float4 kCompositeFarKernel1[kBokehCompositeKernelCount] = {
    float4(0.000115f, 0.009116f, 0.000000f, 0.051147f),
    float4(0.005324f, 0.013416f, 0.009311f, 0.075276f),
    float4(0.013753f, 0.016519f, 0.024376f, 0.092685f),
    float4(0.024700f, 0.017215f, 0.043940f, 0.096591f),
    float4(0.036693f, 0.015064f, 0.065375f, 0.084521f),
    float4(0.047976f, 0.010684f, 0.085539f, 0.059948f),
    float4(0.057015f, 0.005570f, 0.101695f, 0.031254f),
    float4(0.062782f, 0.001529f, 0.112002f, 0.008578f),
    float4(0.064754f, 0.000000f, 0.115526f, 0.000000f),
    float4(0.062782f, 0.001529f, 0.112002f, 0.008578f),
    float4(0.057015f, 0.005570f, 0.101695f, 0.031254f),
    float4(0.047976f, 0.010684f, 0.085539f, 0.059948f),
    float4(0.036693f, 0.015064f, 0.065375f, 0.084521f),
    float4(0.024700f, 0.017215f, 0.043940f, 0.096591f),
    float4(0.013753f, 0.016519f, 0.024376f, 0.092685f),
    float4(0.005324f, 0.013416f, 0.009311f, 0.075276f),
    float4(0.000115f, 0.009116f, 0.000000f, 0.051147f)
};

static constant float4 kCompositeNearKernel[kBokehCompositeKernelCount] = {
    float4(-0.001442f, 0.026656f, 0.000000f, 0.085609f),
    float4(0.010488f, 0.030945f, 0.017733f, 0.099384f),
    float4(0.023771f, 0.030830f, 0.037475f, 0.099012f),
    float4(0.036356f, 0.026770f, 0.056181f, 0.085976f),
    float4(0.046822f, 0.020140f, 0.071737f, 0.064680f),
    float4(0.054555f, 0.012687f, 0.083231f, 0.040745f),
    float4(0.059606f, 0.006074f, 0.090738f, 0.019507f),
    float4(0.062366f, 0.001584f, 0.094841f, 0.005086f),
    float4(0.063232f, 0.000000f, 0.096128f, 0.000000f),
    float4(0.062366f, 0.001584f, 0.094841f, 0.005086f),
    float4(0.059606f, 0.006074f, 0.090738f, 0.019507f),
    float4(0.054555f, 0.012687f, 0.083231f, 0.040745f),
    float4(0.046822f, 0.020140f, 0.071737f, 0.064680f),
    float4(0.036356f, 0.026770f, 0.056181f, 0.085976f),
    float4(0.023771f, 0.030830f, 0.037475f, 0.099012f),
    float4(0.010488f, 0.030945f, 0.017733f, 0.099384f),
    float4(-0.001442f, 0.026656f, 0.000000f, 0.085609f)
};

static float2 complexMulFragment(float2 p, float2 q) {
    return float2(p.x * q.x - p.y * q.y, p.x * q.y + p.y * q.x);
}

fragment half4 bokehDepthOfFieldCompositeFragment(
    VertexData in [[stage_in]],
    constant BokehDepthOfFieldCompositeUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTexture [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> cocTexture [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> farRTexture [[texture(FragmentTextureCustom2)]],
    texture2d<float, access::sample> farGTexture [[texture(FragmentTextureCustom3)]],
    texture2d<float, access::sample> farBTexture [[texture(FragmentTextureCustom4)]],
    texture2d<float, access::sample> nearRTexture [[texture(FragmentTextureCustom5)]],
    texture2d<float, access::sample> nearGTexture [[texture(FragmentTextureCustom6)]],
    texture2d<float, access::sample> nearBTexture [[texture(FragmentTextureCustom7)]],
    texture2d<float, access::sample> nearCoCTexture [[texture(FragmentTextureCustom8)]],
    texture2d<float, access::sample> farWeightsTexture [[texture(FragmentTextureCustom9)]],
    texture2d<float, access::sample> nearCoCBoxTexture [[texture(FragmentTextureCustom10)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler pointSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float4 sharpSample = colorTexture.sample(linearSampler, uv);
    const float4 cocSample = cocTexture.sample(pointSampler, uv);
    const float farCoC = cocSample.y;
    const float nearCoC = nearCoCTexture.sample(pointSampler, uv).x;
    const float nearSoftCoC = nearCoCBoxTexture.sample(linearSampler, uv).x;

    const uint2 farTextureSize = uint2(farRTexture.get_width(), farRTexture.get_height());
    const float2 texelSize = 1.0f / float2(farTextureSize);

    float4 farColor = 0.0f;
    if (farCoC > kBokehCompositeCoCActivationThreshold) {
        float4 farRedAccum = 0.0f;
        float4 farGreenAccum = 0.0f;
        float4 farBlueAccum = 0.0f;
        float farWeightAccum = 0.0f;

        for (int i = -kBokehCompositeKernelRadius; i <= kBokehCompositeKernelRadius; ++i) {
            const uint kernelIndex = uint(i + kBokehCompositeKernelRadius);
            const float2 sampleUV = uv + (texelSize * float2(0.0f, float(i)) * uniforms.maxRadius);
            const bool usesCenter = cocTexture.sample(pointSampler, sampleUV).y <= kBokehCompositeCoCActivationThreshold;
            const float2 resolvedUV = usesCenter ? uv : sampleUV;

            const float4 farRedSample = farRTexture.sample(linearSampler, resolvedUV);
            const float4 farGreenSample = farGTexture.sample(linearSampler, resolvedUV);
            const float4 farBlueSample = farBTexture.sample(linearSampler, resolvedUV);

            farRedAccum.xy += complexMulFragment(float2(farRedSample.x, farRedSample.y), kCompositeFarKernel0[kernelIndex].xy);
            farRedAccum.zw += complexMulFragment(float2(farRedSample.z, farRedSample.w), kCompositeFarKernel1[kernelIndex].xy);
            farGreenAccum.xy += complexMulFragment(float2(farGreenSample.x, farGreenSample.y), kCompositeFarKernel0[kernelIndex].xy);
            farGreenAccum.zw += complexMulFragment(float2(farGreenSample.z, farGreenSample.w), kCompositeFarKernel1[kernelIndex].xy);
            farBlueAccum.xy += complexMulFragment(float2(farBlueSample.x, farBlueSample.y), kCompositeFarKernel0[kernelIndex].xy);
            farBlueAccum.zw += complexMulFragment(float2(farBlueSample.z, farBlueSample.w), kCompositeFarKernel1[kernelIndex].xy);
            farWeightAccum += farWeightsTexture.sample(linearSampler, resolvedUV).x;
        }

        const float normalization = max(farWeightAccum * (1.0f / 17.0f), 1.0e-4f);
        farColor = float4(
            dot(farRedAccum.xy, float2(0.411259f, -0.548794f)) + dot(farRedAccum.zw, float2(0.513282f, 4.561110f)),
            dot(farGreenAccum.xy, float2(0.411259f, -0.548794f)) + dot(farGreenAccum.zw, float2(0.513282f, 4.561110f)),
            dot(farBlueAccum.xy, float2(0.411259f, -0.548794f)) + dot(farBlueAccum.zw, float2(0.513282f, 4.561110f)),
            0.0f
        ) / normalization;
    }

    float2 nearRedAccum = 0.0f;
    float2 nearGreenAccum = 0.0f;
    float2 nearBlueAccum = 0.0f;
    float nearWeightAccum = 0.0f;

    for (int i = -kBokehCompositeKernelRadius; i <= kBokehCompositeKernelRadius; ++i) {
        const uint kernelIndex = uint(i + kBokehCompositeKernelRadius);
        const float2 sampleUV = uv + (texelSize * float2(0.0f, float(i)) * uniforms.maxRadius);
        const float sampledNearCoC = nearCoCTexture.sample(pointSampler, sampleUV).x;
        const bool usesCenter = sampledNearCoC <= kBokehCompositeCoCActivationThreshold;
        const float2 resolvedUV = usesCenter ? uv : sampleUV;

        const float4 nearRedSample = nearRTexture.sample(linearSampler, resolvedUV);
        const float4 nearGreenSample = nearGTexture.sample(linearSampler, resolvedUV);
        const float4 nearBlueSample = nearBTexture.sample(linearSampler, resolvedUV);

        nearRedAccum += complexMulFragment(float2(nearRedSample.x, nearRedSample.y), kCompositeNearKernel[kernelIndex].xy);
        nearGreenAccum += complexMulFragment(float2(nearGreenSample.x, nearGreenSample.y), kCompositeNearKernel[kernelIndex].xy);
        nearBlueAccum += complexMulFragment(float2(nearBlueSample.x, nearBlueSample.y), kCompositeNearKernel[kernelIndex].xy);
        nearWeightAccum += nearRedSample.z;
    }

    const float4 nearColor = float4(
        dot(nearRedAccum, float2(0.767583f, 1.862321f)),
        dot(nearGreenAccum, float2(0.767583f, 1.862321f)),
        dot(nearBlueAccum, float2(0.767583f, 1.862321f)),
        0.0f
    );

    const float farBlend = clamp(farCoC * uniforms.blend, 0.0f, 1.0f);
    const float gatheredNearSupport = clamp(nearWeightAccum * (1.0f / 17.0f), 0.0f, 1.0f);
    const float nearBlendField = max(nearCoC, nearSoftCoC * gatheredNearSupport);
    const float nearBlend = clamp(nearBlendField * uniforms.blend, 0.0f, 1.0f);
    const float3 farComposite = mix(sharpSample.rgb, farColor.rgb, farBlend);
    const float3 finalColor = mix(farComposite, nearColor.rgb, nearBlend);
    const float blurCoverage = max(farBlend, nearBlend);
    const float finalAlpha = max(sharpSample.a, blurCoverage);

    // Fabric reuses the DOF output as an image, so alpha needs to preserve the sharp image while
    // also allowing blur coverage to spill over cleared background.
    return half4(half3(finalColor), half(finalAlpha));
}
