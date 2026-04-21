typedef struct {
    float strength;
    int samples;
    float deltaTime;
    float jitter;
    int frame;
} MotionBlurUniforms;

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
    texture2d<float, access::read> blueNoiseTex [[texture(FragmentTextureCustom2)]]) {

    constexpr sampler s(filter::linear, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float2 vel = velocityTex.sample(s, uv).rg;

    // Skip sampling for static pixels.
    if (dot(vel, vel) < 1e-9) {
        return half4(colorTex.sample(s, uv));
    }

    const float dt = max(uniforms.deltaTime, 1e-4);
    const float2 velocity = vel * (uniforms.strength / dt);

    // Animate blue noise lookup position per frame using PCG4D.
    const uint frame = uint(uniforms.frame);
    uint4 seed = uint4(frame, frame * 15843u, frame * 31u + 4566u, frame * 2345u + 58585u);
    pcg4d(seed);
    const uint2 noiseCoord = (uint2(in.position.xy) + seed.xy) % uint2(blueNoiseTex.get_width(), blueNoiseTex.get_height());
    const float2 noise = blueNoiseTex.read(noiseCoord).rg * 2.0 - 1.0;
    const float2 jitteredVelocity = velocity + noise * uniforms.jitter * velocity;

    const int numSamples = clamp(uniforms.samples, 1, 32);
    float4 color = float4(0.0);
    for (int i = 0; i < numSamples; i++) {
        const float t = float(i) / float(numSamples - 1) - 0.5;
        color += colorTex.sample(s, uv + jitteredVelocity * t);
    }
    return half4(color / float(numSamples));
}
