typedef struct {
    float strength;
    int samples;
} MotionBlurUniforms;

fragment half4 motionBlurFragment(
    VertexData in [[stage_in]],
    constant MotionBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> velocityTex [[texture(FragmentTextureCustom1)]]) {

    constexpr sampler s(filter::linear, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float2 velocity = velocityTex.sample(s, uv).rg * uniforms.strength;

    const int numSamples = clamp(uniforms.samples, 1, 32);
    float4 color = float4(0.0);
    for (int i = 0; i < numSamples; i++) {
        const float t = float(i) / float(numSamples - 1) - 0.5;
        color += colorTex.sample(s, uv + velocity * t);
    }
    return half4(color / float(numSamples));
}
