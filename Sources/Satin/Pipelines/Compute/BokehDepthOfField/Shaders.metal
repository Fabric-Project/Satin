// BokehDepthOfField compute pipeline
//
// This is a Satin-native port of the separable circular DOF reference path documented by:
// - Kleber Garcia, "Circular Depth of Field", GDC 2018
// - the related ACM talk/paper cited from the original shader comments
// - Erfan Ahmadi's BokehDepthOfField separable Metal implementation
//
// The pass graph intentionally mirrors the reference structure:
// 1. full-res near/far CoC generation
// 2. half-res downsample for CoC, center color, and color*farCoC
// 3. near CoC box filter
// 4. near CoC max filter
// 5. horizontal DOF accumulation
// The vertical pass and final blend are performed in the composite fragment shader.

typedef struct {
    int2 size;
    float nearPlane;
    float farPlane;
    float nearBegin;
    float nearEnd;
    float farBegin;
    float farEnd;
    float cocPadding0;
    float cocPadding1;
} BokehDepthOfFieldGenerateCoCUniforms;

typedef struct {
    int2 size;
    float farBoost;
    float downsamplePadding;
} BokehDepthOfFieldDownsampleUniforms;

typedef struct {
    int2 size;
    int filterRadius;
    float nearCoCPadding;
} BokehDepthOfFieldNearCoCUniforms;

typedef struct {
    int2 size;
    float maxRadius;
    float horizontalPadding;
} BokehDepthOfFieldHorizontalUniforms;

constant int kNearCoCFilterRadius = 6;
constant int kKernelRadius = 8;
constant int kKernelCount = 17;
constant float kCoCActivationThreshold = 1.0e-3f;

// Far blur kernels (2 components).
static constant float4 kFarKernel0[kKernelCount] = {
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

static constant float4 kFarKernel1[kKernelCount] = {
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

// Near blur kernel (1 component).
static constant float4 kNearKernel[kKernelCount] = {
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

static float2 complexMul(float2 p, float2 q) {
    return float2(p.x * q.x - p.y * q.y, p.x * q.y + p.y * q.x);
}

static float linearViewDepthFromReferenceDepth(float normalizedDepth, float nearPlane, float farPlane) {
    const float clipDepth = (2.0f * normalizedDepth) - 1.0f;
    const float denominator = (farPlane + nearPlane) - (clipDepth * (farPlane - nearPlane));
    return max(((2.0f * nearPlane) * farPlane) / max(denominator, 1.0e-6f), 0.0f);
}

static float2 computeNearFarCoC(
    float viewDistance,
    float nearBegin,
    float nearEnd,
    float farBegin,
    float farEnd
) {
    const float nearDenominator = max(nearEnd - nearBegin, 1.0e-4f);
    const float farDenominator = max(farEnd - farBegin, 1.0e-4f);

    // Match the reference CoC generation: keep the raw near/far ramps here and clamp only
    // at the later blend/use sites that require bounded masks.
    const float nearCoC = (nearEnd - viewDistance) / nearDenominator;
    const float farCoC = (viewDistance - farBegin) / farDenominator;
    return float2(nearCoC, farCoC);
}

kernel void bokehDepthOfFieldGenerateCoCUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldGenerateCoCUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> cocTexture [[texture(ComputeTextureCustom0)]],
    depth2d<float, access::sample> depthTexture [[texture(ComputeTextureCustom1)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    constexpr sampler pointSampler(filter::nearest, address::clamp_to_edge);
    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float reversedZDepth = depthTexture.sample(pointSampler, uv);
    const float normalizedDepth = 1.0f - reversedZDepth;
    const float viewDistance = linearViewDepthFromReferenceDepth(
        normalizedDepth,
        uniforms.nearPlane,
        uniforms.farPlane
    );
    const float2 coc = computeNearFarCoC(
        viewDistance,
        uniforms.nearBegin,
        uniforms.nearEnd,
        uniforms.farBegin,
        uniforms.farEnd
    );

    cocTexture.write(float4(coc, 0.0f, 0.0f), gid);
}

kernel void bokehDepthOfFieldDownsampleUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldDownsampleUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> downsampledCoCTexture [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::write> sourceColorTexture [[texture(ComputeTextureCustom1)]],
    texture2d<float, access::write> colorMulFarTexture [[texture(ComputeTextureCustom2)]],
    texture2d<float, access::sample> fullResolutionCoCTexture [[texture(ComputeTextureCustom3)]],
    texture2d<float, access::sample> fullResolutionColorTexture [[texture(ComputeTextureCustom4)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    constexpr sampler pointSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    // The reference shader assumes an exact half-resolution target, where each output pixel covers
    // a 2x2 footprint in the full-resolution inputs and the representative corner samples sit at
    // +/- 0.5 source texels from the footprint center. Satin exposes arbitrary processing scales,
    // so derive the quarter-footprint offsets from the actual output resolution instead of
    // hardcoding the half-resolution spacing.
    const float2 quarterFootprintOffset = 0.25f / float2(size);

    const float2 sampleUV0 = uv + float2(-quarterFootprintOffset.x, -quarterFootprintOffset.y);
    const float2 sampleUV1 = uv + float2(quarterFootprintOffset.x, -quarterFootprintOffset.y);
    const float2 sampleUV2 = uv + float2(-quarterFootprintOffset.x, quarterFootprintOffset.y);
    const float2 sampleUV3 = uv + float2(quarterFootprintOffset.x, quarterFootprintOffset.y);

    const float4 coc0 = fullResolutionCoCTexture.sample(pointSampler, sampleUV0);
    const float4 coc1 = fullResolutionCoCTexture.sample(pointSampler, sampleUV1);
    const float4 coc2 = fullResolutionCoCTexture.sample(pointSampler, sampleUV2);
    const float4 coc3 = fullResolutionCoCTexture.sample(pointSampler, sampleUV3);

    // Seed the near-mask chain conservatively from the full-res 2x2 footprint so thin foreground
    // silhouettes survive downsampling and can spill correctly over cleared background.
    const float near0 = max(coc0.x, 0.0f);
    const float near1 = max(coc1.x, 0.0f);
    const float near2 = max(coc2.x, 0.0f);
    const float near3 = max(coc3.x, 0.0f);
    const float centerNearCoC = max(max(near0, near1), max(near2, near3));

    const float far0 = saturate(coc0.y * uniforms.farBoost);
    const float centerFarCoC = far0;
    const float far1 = saturate(coc1.y * uniforms.farBoost);
    const float far2 = saturate(coc2.y * uniforms.farBoost);
    const float far3 = saturate(coc3.y * uniforms.farBoost);

    const float weight0 = 1000.0f;
    const float weight1 = 1.0f / (abs(centerFarCoC - far1) + 0.001f);
    const float weight2 = 1.0f / (abs(centerFarCoC - far2) + 0.001f);
    const float weight3 = 1.0f / (abs(centerFarCoC - far3) + 0.001f);
    const float weightSum = weight0 + weight1 + weight2 + weight3;

    const float4 color0 = fullResolutionColorTexture.sample(pointSampler, sampleUV0);
    const float4 color1 = fullResolutionColorTexture.sample(pointSampler, sampleUV1);
    const float4 color2 = fullResolutionColorTexture.sample(pointSampler, sampleUV2);
    const float4 color3 = fullResolutionColorTexture.sample(pointSampler, sampleUV3);
    const float4 centerColor = fullResolutionColorTexture.sample(pointSampler, uv);

    const float4 weightedFarColor = (
        color0 * weight0 +
        color1 * weight1 +
        color2 * weight2 +
        color3 * weight3
    ) / max(weightSum, 1.0e-4f);

    downsampledCoCTexture.write(float4(centerNearCoC, centerFarCoC, 0.0f, 0.0f), gid);
    sourceColorTexture.write(centerColor, gid);
    colorMulFarTexture.write(weightedFarColor * centerFarCoC, gid);
}

static float boxFilterNearCoC(texture2d<float, access::sample> nearCoCTexture, float2 uv, float2 stepOffset, int filterRadius) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float sum = 0.0f;
    for (int i = 0; i <= filterRadius * 2; ++i) {
        const int index = i - filterRadius;
        const float2 sampleUV = uv + stepOffset * float(index);
        sum += nearCoCTexture.sample(linearSampler, sampleUV).x;
    }
    return sum / float(filterRadius * 2 + 1);
}

static float maxFilterNearCoC(texture2d<float, access::sample> nearCoCTexture, float2 uv, float2 stepOffset, int filterRadius) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float maxValue = 0.0f;
    for (int i = 0; i <= filterRadius * 2; ++i) {
        const int index = i - filterRadius;
        const float2 sampleUV = uv + stepOffset * float(index);
        maxValue = max(maxValue, nearCoCTexture.sample(linearSampler, sampleUV).x);
    }
    return maxValue;
}

kernel void bokehDepthOfFieldNearCoCBoxHorizontalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldNearCoCUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> outputTexture [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::sample> inputTexture [[texture(ComputeTextureCustom1)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    const int filterRadius = max(uniforms.filterRadius, 0);
    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float2 stepOffset = float2(1.0f / float(size.x), 0.0f);
    const float value = boxFilterNearCoC(inputTexture, uv, stepOffset, filterRadius);
    outputTexture.write(float4(value, 0.0f, 0.0f, 0.0f), gid);
}

kernel void bokehDepthOfFieldNearCoCBoxVerticalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldNearCoCUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> outputTexture [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::sample> inputTexture [[texture(ComputeTextureCustom1)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    const int filterRadius = max(uniforms.filterRadius, 0);
    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float2 stepOffset = float2(0.0f, 1.0f / float(size.y));
    const float value = boxFilterNearCoC(inputTexture, uv, stepOffset, filterRadius);
    outputTexture.write(float4(value, 0.0f, 0.0f, 0.0f), gid);
}

kernel void bokehDepthOfFieldNearCoCMaxHorizontalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldNearCoCUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> outputTexture [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::sample> inputTexture [[texture(ComputeTextureCustom1)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    const int filterRadius = max(uniforms.filterRadius, 0);
    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float2 stepOffset = float2(1.0f / float(size.x), 0.0f);
    const float value = maxFilterNearCoC(inputTexture, uv, stepOffset, filterRadius);
    outputTexture.write(float4(value, 0.0f, 0.0f, 0.0f), gid);
}

kernel void bokehDepthOfFieldNearCoCMaxVerticalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldNearCoCUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> outputTexture [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::sample> inputTexture [[texture(ComputeTextureCustom1)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    const int filterRadius = max(uniforms.filterRadius, 0);
    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float2 stepOffset = float2(0.0f, 1.0f / float(size.y));
    const float value = maxFilterNearCoC(inputTexture, uv, stepOffset, filterRadius);
    outputTexture.write(float4(value, 0.0f, 0.0f, 0.0f), gid);
}

kernel void bokehDepthOfFieldHorizontalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldHorizontalUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> farRTexture [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::write> farGTexture [[texture(ComputeTextureCustom1)]],
    texture2d<float, access::write> farBTexture [[texture(ComputeTextureCustom2)]],
    texture2d<float, access::write> nearRTexture [[texture(ComputeTextureCustom3)]],
    texture2d<float, access::write> nearGTexture [[texture(ComputeTextureCustom4)]],
    texture2d<float, access::write> nearBTexture [[texture(ComputeTextureCustom5)]],
    texture2d<float, access::write> farWeightsTexture [[texture(ComputeTextureCustom6)]],
    texture2d<float, access::sample> sourceColorTexture [[texture(ComputeTextureCustom7)]],
    texture2d<float, access::sample> cocTexture [[texture(ComputeTextureCustom8)]],
    texture2d<float, access::sample> nearCoCTexture [[texture(ComputeTextureCustom9)]],
    texture2d<float, access::sample> colorMulFarTexture [[texture(ComputeTextureCustom10)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler pointSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float2 texelSize = 1.0f / float2(size);

    const float4 cocSample = cocTexture.sample(pointSampler, uv);
    const float nearCoC = nearCoCTexture.sample(pointSampler, uv).x;

    float4 farRedAccum = 0.0f;
    float4 farGreenAccum = 0.0f;
    float4 farBlueAccum = 0.0f;
    float farWeightAccum = 0.0f;

    for (int i = -kKernelRadius; i <= kKernelRadius; ++i) {
        const uint kernelIndex = uint(i + kKernelRadius);
        const float2 sampleUV = uv + (texelSize * float2(float(i), 0.0f) * uniforms.maxRadius);
        const float sampledFarCoC = cocTexture.sample(pointSampler, sampleUV).y;
        if (sampledFarCoC > kCoCActivationThreshold) {
            const float4 farColor = colorMulFarTexture.sample(pointSampler, sampleUV);

            farRedAccum.xy += complexMul(kFarKernel0[kernelIndex].xy, float2(farColor.x, 0.0f));
            farRedAccum.zw += complexMul(kFarKernel1[kernelIndex].xy, float2(farColor.x, 0.0f));
            farGreenAccum.xy += complexMul(kFarKernel0[kernelIndex].xy, float2(farColor.y, 0.0f));
            farGreenAccum.zw += complexMul(kFarKernel1[kernelIndex].xy, float2(farColor.y, 0.0f));
            farBlueAccum.xy += complexMul(kFarKernel0[kernelIndex].xy, float2(farColor.z, 0.0f));
            farBlueAccum.zw += complexMul(kFarKernel1[kernelIndex].xy, float2(farColor.z, 0.0f));

            farWeightAccum += sampledFarCoC;
        }
    }
    farWeightAccum *= 1.0f / 17.0f;

    float2 nearRedAccum = 0.0f;
    float2 nearGreenAccum = 0.0f;
    float2 nearBlueAccum = 0.0f;
    float nearWeightAccum = 0.0f;

    for (int i = -kKernelRadius; i <= kKernelRadius; ++i) {
        const uint kernelIndex = uint(i + kKernelRadius);
        const float2 sampleUV = uv + (texelSize * float2(float(i), 0.0f) * uniforms.maxRadius);
        const float sampledNearCoC = nearCoCTexture.sample(pointSampler, sampleUV).x;
        const bool usesCenter = sampledNearCoC <= kCoCActivationThreshold;
        const float2 resolvedUV = usesCenter ? uv : sampleUV;
        const float4 colorSample = sourceColorTexture.sample(linearSampler, resolvedUV);

        nearRedAccum += complexMul(kNearKernel[kernelIndex].xy, float2(colorSample.x, 0.0f));
        nearGreenAccum += complexMul(kNearKernel[kernelIndex].xy, float2(colorSample.y, 0.0f));
        nearBlueAccum += complexMul(kNearKernel[kernelIndex].xy, float2(colorSample.z, 0.0f));
        nearWeightAccum += sampledNearCoC;
    }
    nearWeightAccum *= 1.0f / 17.0f;

    farRTexture.write(farRedAccum, gid);
    farGTexture.write(farGreenAccum, gid);
    farBTexture.write(farBlueAccum, gid);
    nearRTexture.write(float4(nearRedAccum, nearWeightAccum, 1.0f), gid);
    nearGTexture.write(float4(nearGreenAccum, nearWeightAccum, 1.0f), gid);
    nearBTexture.write(float4(nearBlueAccum, nearWeightAccum, 1.0f), gid);
    farWeightsTexture.write(float4(farWeightAccum, 0.0f, 0.0f, 0.0f), gid);
}
