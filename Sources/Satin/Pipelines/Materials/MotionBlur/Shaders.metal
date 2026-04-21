typedef struct {
    float shutterAngle;
    int samples;
    float jitter;
    int frame;
} MotionBlurUniforms;
constant float kMaxShutterAngle = 720.0f;

// PCG4D hash — animates blue noise sample position per frame
static void pcg4d(thread uint4& v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w; v.y += v.z * v.x;
    v.z += v.x * v.y; v.w += v.y * v.z;
    v ^= v >> 16u;
    v.x += v.y * v.w; v.y += v.z * v.x;
    v.z += v.x * v.y; v.w += v.y * v.z;
}

fragment half4 motionBlurFragment(
    VertexData in [[stage_in]],
    constant MotionBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> velocityTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::read> blueNoiseTex [[texture(FragmentTextureCustom2)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom3)]]) {

    constexpr sampler colorSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler depthSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;

    // Nearest-neighbor velocity prevents bilinear blending of foreground/background
    // velocity values across depth-discontinuity edges.
    constexpr sampler velSampler(filter::nearest, address::clamp_to_edge);
    const float2 vel = velocityTex.sample(velSampler, uv).rg;

    const float shutterFraction = clamp(uniforms.shutterAngle, 0.0f, kMaxShutterAngle) / 360.0f;
    if (dot(vel, vel) < 1e-9 || shutterFraction <= 1e-6f) {
        return half4(colorTex.sample(colorSampler, uv));
    }

    // Velocity is stored as one frame of UV-space screen motion, so shutter angle directly
    // controls what fraction of that frame interval contributes to blur.
    const float2 velocity = vel * shutterFraction;

    // Animate blue noise lookup position per frame using PCG4D.
    const uint frame = uint(uniforms.frame);
    uint4 seed = uint4(frame, frame * 15843u, frame * 31u + 4566u, frame * 2345u + 58585u);
    pcg4d(seed);
    const uint2 noiseCoord = (uint2(in.position.xy) + seed.xy) % uint2(blueNoiseTex.get_width(), blueNoiseTex.get_height());
    // One blue-noise value drives the golden-ratio sequence base, breaking inter-frame coherence.
    const float baseNoise = blueNoiseTex.read(noiseCoord).r;

    const float centerDepth = depthTex.sample(depthSampler, uv);
    const bool hasValidDepth = centerDepth > 0.0f && centerDepth < 1.0f;

    const int numSamples = clamp(uniforms.samples, 1, 32);
    float4 color = float4(0.0);
    float totalWeight = 0.0;

    for (int i = 0; i < numSamples; i++) {
        // Per-sample stratified jitter via golden-ratio low-discrepancy sequence.
        // jitter=1 → each sample at a random position within its stratum (no banding).
        // jitter=0 → each sample at stratum centre (uniform grid).
        const float r = fract(baseNoise + float(i) * 0.618033988f);
        const float t = numSamples == 1
            ? 0.0f
            : (float(i) + mix(0.5f, r, uniforms.jitter)) / float(numSamples) - 0.5f;
        const float2 sampleUV = uv + velocity * t;
        const float sampleDistance = abs(t) * 2.0f;
        const float centerWeight = mix(0.25f, 1.0f, 1.0f - smoothstep(0.0f, 1.0f, sampleDistance));

        float depthWeight = 1.0f;
        if (hasValidDepth) {
            const float sampleDepth = depthTex.sample(depthSampler, sampleUV);
            // Satin uses reversed-Z depth: larger values are closer to the camera.
            // Fade out samples that sit behind the center pixel to avoid pulling
            // background color across foreground silhouettes.
            const float backgroundDepthDelta = max(centerDepth - sampleDepth, 0.0f);
            depthWeight = 1.0f - smoothstep(0.0015f, 0.006f, backgroundDepthDelta);
        }

        const float sampleWeight = centerWeight * depthWeight;
        if (sampleWeight <= 0.0f) { continue; }

        color += colorTex.sample(colorSampler, sampleUV) * sampleWeight;
        totalWeight += sampleWeight;
    }

    if (totalWeight > 0.0f) {
        return half4(color / totalWeight);
    }
    return half4(colorTex.sample(colorSampler, uv));
}
