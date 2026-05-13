// BokehDepthOfField compute pipeline
//
// Reference lineage:
// - "Circular Dof" by Kleber Garcia ("Kecho"), simplified on Shadertoy:
//   https://shadertoy.com/view/Xd2BWc
// - Kleber Garcia, "Circular Depth of Field", GDC 2018:
//   https://media.gdcvault.com/gdc2018/presentations/Garcia_Kleber_CircularDepthOf.pdf
// - Related ACM reference cited by the original shader comments:
//   http://dl.acm.org/citation.cfm?id=3085022
//
// Satin uses a split near/far prefilter, a near-radius max filter, then complex separable blur passes.
// It is intentionally close in spirit to Frostbite-style circular DOF, but it is not a direct port.
//
// Debugging notes for current artifact investigation:
// - Cleared depth currently falls into the "max far blur" path in the prefilter stage below.
// - That can create silhouette-bounded CoC regions when a blurred foreground/background edge overlaps
//   areas where the scene depth is just the clear value.
// - Thin geometry, alpha-tested silhouettes, or partially covered pixels are the first places to inspect
//   when blur appears clipped to object bounds instead of bleeding naturally into background.
//
typedef struct {
    int2 size;
    float4x4 inverseProjectionMatrix;
    float focusDistance;
    float focusRange;
    float maxBlurRadius;
    float prefilterPadding;
} BokehDepthOfFieldPrefilterUniforms;

typedef struct {
    int2 size;
    float maxBlurRadius;
    float splitPadding;
} BokehDepthOfFieldSplitUniforms;

typedef struct {
    int2 size;
} BokehDepthOfFieldComplexUniforms;

typedef struct {
    int2 size;
    int maxRadius;
    float nearMaxPadding;
} BokehDepthOfFieldNearMaxUniforms;

constant int kBokehKernelRadius = 8;
constant int kBokehKernelCount = 17;

static constant float2 kKernel0[kBokehKernelCount] = {
    float2( 0.014096f, -0.022658f),
    float2(-0.020612f, -0.025574f),
    float2(-0.038708f,  0.006957f),
    float2(-0.021449f,  0.040468f),
    float2( 0.013015f,  0.050223f),
    float2( 0.042178f,  0.038585f),
    float2( 0.057972f,  0.019812f),
    float2( 0.063647f,  0.005252f),
    float2( 0.064754f,  0.000000f),
    float2( 0.063647f,  0.005252f),
    float2( 0.057972f,  0.019812f),
    float2( 0.042178f,  0.038585f),
    float2( 0.013015f,  0.050223f),
    float2(-0.021449f,  0.040468f),
    float2(-0.038708f,  0.006957f),
    float2(-0.020612f, -0.025574f),
    float2( 0.014096f, -0.022658f)
};

static constant float2 kKernel1[kBokehKernelCount] = {
    float2(0.000115f, 0.009116f),
    float2(0.005324f, 0.013416f),
    float2(0.013753f, 0.016519f),
    float2(0.024700f, 0.017215f),
    float2(0.036693f, 0.015064f),
    float2(0.047976f, 0.010684f),
    float2(0.057015f, 0.005570f),
    float2(0.062782f, 0.001529f),
    float2(0.064754f, 0.000000f),
    float2(0.062782f, 0.001529f),
    float2(0.057015f, 0.005570f),
    float2(0.047976f, 0.010684f),
    float2(0.036693f, 0.015064f),
    float2(0.024700f, 0.017215f),
    float2(0.013753f, 0.016519f),
    float2(0.005324f, 0.013416f),
    float2(0.000115f, 0.009116f)
};

constant float2 kKernel0Weights = float2(0.411259f, -0.548794f);
constant float2 kKernel1Weights = float2(0.513282f, 4.561110f);

static float2 bokehComplexMul(float2 p, float2 q) {
    return float2(p.x * q.x - p.y * q.y, p.x * q.y + p.y * q.x);
}

static float bokehDepthOfFieldViewDistance(
    float2 uv,
    float depth,
    float4x4 inverseProjectionMatrix
) {
    const float4 clipPosition = float4(uv.x * 2.0f - 1.0f, 1.0f - uv.y * 2.0f, depth, 1.0f);
    const float4 viewPosition = inverseProjectionMatrix * clipPosition;
    return max(-viewPosition.z / max(viewPosition.w, 1.0e-6f), 0.0f);
}

static float bokehDepthOfFieldSignedRadius(
    float viewDistance,
    float focusDistance,
    float focusRange,
    float maxBlurRadius
) {
    const float halfRange = max(focusRange * 0.5f, 1.0e-4f);
    const float falloffRange = max(focusRange, 1.0e-4f);
    const float delta = viewDistance - focusDistance;

    float signedCoC = 0.0f;
    if (delta < -halfRange) {
        signedCoC = (delta + halfRange) / falloffRange;
    } else if (delta > halfRange) {
        signedCoC = (delta - halfRange) / falloffRange;
    }

    return clamp(signedCoC, -1.0f, 1.0f) * maxBlurRadius;
}

kernel void bokehDepthOfFieldPrefilterUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldPrefilterUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> sourceColorTex [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::write> cocTex [[texture(ComputeTextureCustom1)]],
    texture2d<float, access::sample> colorTex [[texture(ComputeTextureCustom4)]],
    depth2d<float, access::sample> depthTex [[texture(ComputeTextureCustom5)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float2 fullTexelSize = 1.0f / float2(colorTex.get_width(), colorTex.get_height());
    const float2 downsampleScale = float2(
        max(float(colorTex.get_width()) / max(float(size.x), 1.0f), 1.0f),
        max(float(colorTex.get_height()) / max(float(size.y), 1.0f), 1.0f)
    );
    const float2 sampleOffset = fullTexelSize * (downsampleScale - 1.0f) * 0.5f;

    const float2 taps[4] = {
        float2(-sampleOffset.x, -sampleOffset.y),
        float2( sampleOffset.x, -sampleOffset.y),
        float2(-sampleOffset.x,  sampleOffset.y),
        float2( sampleOffset.x,  sampleOffset.y)
    };
    float4 colorAccum = 0.0f;
    float cocAccum = 0.0f;
    float cocWeight = 0.0f;
    float maxAbsoluteRadius = 0.0f;

    for (uint i = 0; i < 4; ++i) {
        const float2 sampleUV = clamp(uv + taps[i], 0.0f, 1.0f);
        const float4 colorSample = colorTex.sample(linearSampler, sampleUV);
        const float depth = depthTex.sample(nearestSampler, sampleUV);

        const float viewDistance = bokehDepthOfFieldViewDistance(
            sampleUV,
            depth,
            uniforms.inverseProjectionMatrix
        );
        const float signedRadius = bokehDepthOfFieldSignedRadius(
            viewDistance,
            uniforms.focusDistance,
            uniforms.focusRange,
            uniforms.maxBlurRadius
        );
        const float sourceCoverage = saturate(colorSample.a);
        const float cocContribution = max(abs(signedRadius), 1.0e-4f) * sourceCoverage;

        colorAccum += colorSample * sourceCoverage;
        cocAccum += signedRadius * cocContribution;
        cocWeight += cocContribution;
        maxAbsoluteRadius = max(maxAbsoluteRadius, abs(signedRadius));
    }

    const float averagedCoverage = colorAccum.a * 0.25f;
    const float3 averagedColor = colorAccum.rgb / max(colorAccum.a, 1.0e-4f);
    const float signedRadius = cocAccum / max(cocWeight, 1.0e-4f);

    sourceColorTex.write(float4(averagedColor, averagedCoverage), gid);
    cocTex.write(float4(signedRadius, maxAbsoluteRadius, 0.0f, 1.0f), gid);
}

kernel void bokehDepthOfFieldSplitUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldSplitUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> nearColorTex [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::write> farColorTex [[texture(ComputeTextureCustom1)]],
    texture2d<float, access::write> nearRadiusTex [[texture(ComputeTextureCustom2)]],
    texture2d<float, access::write> farRadiusTex [[texture(ComputeTextureCustom3)]],
    texture2d<float, access::sample> sourceColorTex [[texture(ComputeTextureCustom4)]],
    texture2d<float, access::sample> cocTex [[texture(ComputeTextureCustom5)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    const float4 sourceSample = sourceColorTex.read(gid);
    const float2 cocSample = cocTex.read(gid).rg;
    const float signedRadius = cocSample.x;
    const float maximumRadius = cocSample.y;

    const float inverseMaxBlurRadius = 1.0f / max(uniforms.maxBlurRadius, 1.0e-4f);
    const float nearRadius = max(-signedRadius, 0.0f);
    const float farRadius = max(signedRadius, 0.0f);
    const float nearCoverage = saturate(nearRadius * inverseMaxBlurRadius) * sourceSample.a;
    const float farCoverage = saturate(farRadius * inverseMaxBlurRadius) * sourceSample.a;

    nearColorTex.write(float4(sourceSample.rgb * nearCoverage, nearCoverage), gid);
    farColorTex.write(float4(sourceSample.rgb * farCoverage, farCoverage), gid);
    nearRadiusTex.write(float4(max(nearRadius, maximumRadius * step(0.0f, -signedRadius)), 0.0f, 0.0f, 1.0f), gid);
    farRadiusTex.write(float4(max(farRadius, maximumRadius * step(0.0f, signedRadius)), 0.0f, 0.0f, 1.0f), gid);
}

kernel void bokehDepthOfFieldComplexHorizontalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldComplexUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> accum0Tex [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::write> accum1Tex [[texture(ComputeTextureCustom1)]],
    texture2d<float, access::write> accum2Tex [[texture(ComputeTextureCustom2)]],
    texture2d<float, access::write> accum3Tex [[texture(ComputeTextureCustom3)]],
    texture2d<float, access::sample> sourceTex [[texture(ComputeTextureCustom4)]],
    texture2d<float, access::sample> radiusTex [[texture(ComputeTextureCustom5)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float radius = radiusTex.sample(nearestSampler, uv).r;
//    if (radius <= 1.0e-4f) {
//        accum0Tex.write(float4(0.0f), gid);
//        accum1Tex.write(float4(0.0f), gid);
//        accum2Tex.write(float4(0.0f), gid);
//        accum3Tex.write(float4(0.0f), gid);
//        return;
//    }

    const float2 texelSize = 1.0f / float2(size);

    float4 accum0 = 0.0f;
    float4 accum1 = 0.0f;
    float4 accum2 = 0.0f;
    float4 accum3 = 0.0f;

    for (int i = -kBokehKernelRadius; i <= kBokehKernelRadius; ++i) {
        const int kernelIndex = i + kBokehKernelRadius;
        const float2 sampleUV = uv + float2(float(i) * texelSize.x * radius, 0.0f);
        const float4 sampleValue = sourceTex.sample(linearSampler, sampleUV);
        const float2 kernel0 = kKernel0[kernelIndex];
        const float2 kernel1 = kKernel1[kernelIndex];

        accum0.rg += sampleValue.r * kernel0;
        accum0.ba += sampleValue.g * kernel0;
        accum1.rg += sampleValue.b * kernel0;
        accum1.ba += sampleValue.a * kernel0;

        accum2.rg += sampleValue.r * kernel1;
        accum2.ba += sampleValue.g * kernel1;
        accum3.rg += sampleValue.b * kernel1;
        accum3.ba += sampleValue.a * kernel1;
    }

    accum0Tex.write(accum0, gid);
    accum1Tex.write(accum1, gid);
    accum2Tex.write(accum2, gid);
    accum3Tex.write(accum3, gid);
}

kernel void bokehDepthOfFieldNearMaxHorizontalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldNearMaxUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> outputTex [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::read> inputTex [[texture(ComputeTextureCustom1)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    const int radius = clamp(uniforms.maxRadius, 0, 24);
    float maxValue = 0.0f;

    for (int i = -24; i <= 24; ++i) {
        if (abs(i) > radius) { continue; }
        const int sampleX = clamp(int(gid.x) + i, 0, int(size.x) - 1);
        maxValue = max(maxValue, inputTex.read(uint2(sampleX, gid.y)).r);
    }

    outputTex.write(float4(maxValue, 0.0f, 0.0f, 1.0f), gid);
}

kernel void bokehDepthOfFieldNearMaxVerticalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldNearMaxUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> outputTex [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::read> inputTex [[texture(ComputeTextureCustom1)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    const int radius = clamp(uniforms.maxRadius, 0, 24);
    float maxValue = 0.0f;

    for (int i = -24; i <= 24; ++i) {
        if (abs(i) > radius) { continue; }
        const int sampleY = clamp(int(gid.y) + i, 0, int(size.y) - 1);
        maxValue = max(maxValue, inputTex.read(uint2(gid.x, sampleY)).r);
    }

    outputTex.write(float4(maxValue, 0.0f, 0.0f, 1.0f), gid);
}

kernel void bokehDepthOfFieldComplexVerticalUpdate(
    uint2 gid [[thread_position_in_grid]],
    constant BokehDepthOfFieldComplexUniforms &uniforms [[buffer(ComputeBufferUniforms)]],
    texture2d<float, access::write> outputTex [[texture(ComputeTextureCustom0)]],
    texture2d<float, access::sample> accum0Tex [[texture(ComputeTextureCustom1)]],
    texture2d<float, access::sample> accum1Tex [[texture(ComputeTextureCustom2)]],
    texture2d<float, access::sample> accum2Tex [[texture(ComputeTextureCustom3)]],
    texture2d<float, access::sample> accum3Tex [[texture(ComputeTextureCustom4)]],
    texture2d<float, access::sample> radiusTex [[texture(ComputeTextureCustom5)]]
) {
    const uint2 size = uint2(uniforms.size);
    if (gid.x >= size.x || gid.y >= size.y) { return; }

    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = (float2(gid) + 0.5f) / float2(size);
    const float radius = radiusTex.sample(nearestSampler, uv).r;
//    if (radius <= 1.0e-4f) {
//        outputTex.write(float4(0.0f), gid);
//        return;
//    }

    const float2 texelSize = 1.0f / float2(size);

    float4 sum0 = 0.0f;
    float4 sum1 = 0.0f;
    float4 sum2 = 0.0f;
    float4 sum3 = 0.0f;

    for (int i = -kBokehKernelRadius; i <= kBokehKernelRadius; ++i) {
        const int kernelIndex = i + kBokehKernelRadius;
        const float2 sampleUV = uv + float2(0.0f, float(i) * texelSize.y * radius);
        const float2 kernel0 = kKernel0[kernelIndex];
        const float2 kernel1 = kKernel1[kernelIndex];

        const float4 sample0 = accum0Tex.sample(linearSampler, sampleUV);
        const float4 sample1 = accum1Tex.sample(linearSampler, sampleUV);
        const float4 sample2 = accum2Tex.sample(linearSampler, sampleUV);
        const float4 sample3 = accum3Tex.sample(linearSampler, sampleUV);

        sum0.rg += bokehComplexMul(sample0.rg, kernel0);
        sum0.ba += bokehComplexMul(sample0.ba, kernel0);
        sum1.rg += bokehComplexMul(sample1.rg, kernel0);
        sum1.ba += bokehComplexMul(sample1.ba, kernel0);

        sum2.rg += bokehComplexMul(sample2.rg, kernel1);
        sum2.ba += bokehComplexMul(sample2.ba, kernel1);
        sum3.rg += bokehComplexMul(sample3.rg, kernel1);
        sum3.ba += bokehComplexMul(sample3.ba, kernel1);
    }

    float4 result = float4(
        dot(sum0.rg, kKernel0Weights) + dot(sum2.rg, kKernel1Weights),
        dot(sum0.ba, kKernel0Weights) + dot(sum2.ba, kKernel1Weights),
        dot(sum1.rg, kKernel0Weights) + dot(sum3.rg, kKernel1Weights),
        dot(sum1.ba, kKernel0Weights) + dot(sum3.ba, kKernel1Weights)
    );
    result = max(result, 0.0f);
    outputTex.write(result, gid);
}
