typedef struct {
    float shutterAngle; // slider,0,92160,180
    int samples;        // slider,1,32,16
    float jitter;       // slider,0,1,1
    int frame;
} MotionBlurUniforms;
constant float kMaxShutterAngle = 92160.0f;
constant float kDepthSoftness = 0.0025f;

// PCG4D hash — animates blue noise sample position per frame
static void pcg4d(thread uint4& v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w; v.y += v.z * v.x;
    v.z += v.x * v.y; v.w += v.y * v.z;
    v ^= v >> 16u;
    v.x += v.y * v.w; v.y += v.z * v.x;
    v.z += v.x * v.y; v.w += v.y * v.z;
}

static float softDepthCompare(float closerDepth, float fartherDepth) {
    return smoothstep(0.0f, kDepthSoftness, closerDepth - fartherDepth);
}

static float motionRadius(float2 velocity, float pixelRadius) {
    return max(length(velocity) * 0.5f, pixelRadius);
}

static float coneWeight(float distance, float radius) {
    return clamp(1.0f - distance / max(radius, 1e-6f), 0.0f, 1.0f);
}

static float cylinderWeight(float distance, float radius) {
    return 1.0f - smoothstep(radius * 0.95f, radius, distance);
}

fragment half4 motionBlurFragment(
    VertexData in [[stage_in]],
    constant MotionBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> velocityTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::read> blueNoiseTex [[texture(FragmentTextureCustom2)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom3)]],
    texture2d<float, access::read> neighborMaxTex [[texture(FragmentTextureCustom4)]]) {

    constexpr sampler colorSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler depthSampler(filter::nearest, address::clamp_to_edge);
    constexpr sampler velSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float2 texelSize = 1.0f / float2(velocityTex.get_width(), velocityTex.get_height());
    const float pixelRadius = max(texelSize.x, texelSize.y) * 0.5f;
    const float4 centerColor = colorTex.sample(colorSampler, uv);

    // Nearest-neighbor velocity prevents bilinear blending of foreground/background
    // velocity values across depth-discontinuity edges.
    const float2 centerVelocityRaw = velocityTex.sample(velSampler, uv).rg;

    const float shutterFraction = clamp(uniforms.shutterAngle, 0.0f, kMaxShutterAngle) / 360.0f;
    if (shutterFraction <= 1e-6f) {
        return half4(centerColor);
    }

    const uint2 dominantCoord = min(uint2(in.position.xy), uint2(neighborMaxTex.get_width() - 1, neighborMaxTex.get_height() - 1));
    const float2 dominantVelocityRaw = neighborMaxTex.read(dominantCoord).rg;
    const float2 dominantVelocity = dominantVelocityRaw * shutterFraction;
    const float dominantSpeed = length(dominantVelocity);
    if (dominantSpeed <= pixelRadius) {
        return half4(centerColor);
    }

    const float2 centerVelocity = centerVelocityRaw * shutterFraction;
    const float centerRadius = motionRadius(centerVelocity, pixelRadius);
    const float centerSpeed = length(centerVelocity);
    const bool borrowNeighborhoodVelocity = centerSpeed <= pixelRadius;
    const float2 blurVelocity = borrowNeighborhoodVelocity ? dominantVelocity : centerVelocity;
    const float blurRadius = motionRadius(blurVelocity, pixelRadius);
    const float centerDepth = depthTex.sample(depthSampler, uv);
    const bool hasValidDepth = centerDepth > 0.0f && centerDepth < 1.0f;

    // Animate blue noise lookup position per frame using PCG4D.
    const uint frame = uint(uniforms.frame);
    uint4 seed = uint4(frame, frame * 15843u, frame * 31u + 4566u, frame * 2345u + 58585u);
    pcg4d(seed);
    const uint2 noiseCoord = (uint2(in.position.xy) + seed.xy) % uint2(blueNoiseTex.get_width(), blueNoiseTex.get_height());
    // One blue-noise value drives the golden-ratio sequence base, breaking inter-frame coherence.
    const float baseNoise = blueNoiseTex.read(noiseCoord).r;

    const int adaptiveSamples = int(ceil(blurRadius / max(pixelRadius * 1.5f, 1e-6f)));
    const int numSamples = clamp(max(uniforms.samples, adaptiveSamples), 1, 64);
    if (numSamples == 1) {
        return half4(centerColor);
    }

    float4 color = centerColor;
    float totalWeight = 1.0f;
    const float centerSkipThreshold = 0.5f / float(numSamples);

    for (int i = 0; i < numSamples; i++) {
        // Per-sample stratified jitter via golden-ratio low-discrepancy sequence.
        // jitter=1 → each sample at a random position within its stratum (no banding).
        // jitter=0 → each sample at stratum centre (uniform grid).
        const float r = fract(baseNoise + float(i) * 0.618033988f);
        const float t = (float(i) + mix(0.5f, r, uniforms.jitter)) / float(numSamples) - 0.5f;
        if (abs(t) <= centerSkipThreshold) { continue; }

        const float2 sampleUV = uv + blurVelocity * t;
        const float sampleDistance = length(sampleUV - uv);
        const float normalizedDistance = sampleDistance / max(blurRadius, pixelRadius);
        const float centerWeight = mix(0.25f, 1.0f, 1.0f - smoothstep(0.0f, 1.0f, normalizedDistance));
        const float sampleDepth = depthTex.sample(depthSampler, sampleUV);
        const bool sampleHasValidDepth = sampleDepth > 0.0f && sampleDepth < 1.0f;
        const float2 sampleVelocity = velocityTex.sample(velSampler, sampleUV).rg * shutterFraction;
        const float sampleRadius = max(motionRadius(sampleVelocity, pixelRadius), borrowNeighborhoodVelocity ? blurRadius * 0.35f : pixelRadius);

        float sampleWeight = 0.0f;
        if (hasValidDepth && sampleHasValidDepth) {
            const float foregroundWeight = softDepthCompare(sampleDepth, centerDepth);
            const float backgroundWeight = softDepthCompare(centerDepth, sampleDepth);
            const float foregroundContribution = foregroundWeight * coneWeight(sampleDistance, sampleRadius);
            const float backgroundContribution = backgroundWeight * coneWeight(sampleDistance, centerRadius);
            const float overlapContribution = cylinderWeight(sampleDistance, sampleRadius) * cylinderWeight(sampleDistance, centerRadius) * 2.0f;
            sampleWeight = foregroundContribution + backgroundContribution + overlapContribution;
        } else {
            sampleWeight = coneWeight(sampleDistance, max(sampleRadius, blurRadius));
        }

        sampleWeight *= centerWeight;
        if (sampleWeight <= 0.0f) { continue; }

        color += colorTex.sample(colorSampler, sampleUV) * sampleWeight;
        totalWeight += sampleWeight;
    }

    return half4(color / totalWeight);
}
