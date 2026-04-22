typedef struct {
    // depth sensitivity; higher keeps AO sharper at edges
    float sharpness;   // slider,1.0,2000.0,500.0, Sharpness
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
    depth2d<float, access::sample> depthTex  [[texture(FragmentTextureCustom1)]]
) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    const float2 uv = in.texcoord;

    const float centerDepth = depthTex.sample(s, uv);
    // Reversed-Z: background cleared to 0.0 — no AO needed.
    if (centerDepth <= 0.0) return 1.0h;

    const int radius = clamp(uniforms.blurRadius, 0, 4);
    if (radius == 0) return ssaoTex.sample(s, uv).r;

    const float2 texelSize = float2(
        1.0 / float(ssaoTex.get_width()),
        1.0 / float(ssaoTex.get_height())
    );
    const float2 sampleStep = passUniforms.direction * texelSize;

    half  totalAO     = 0.0h;
    float totalWeight = 0.0;

    for (int i = -radius; i <= radius; i++) {
        const float2 sampleUV = uv + sampleStep * float(i);
        const float sampleDepth = depthTex.sample(s, sampleUV);
        // Bilateral weight: penalise samples whose depth differs from the centre.
        const float weight = exp(-abs(centerDepth - sampleDepth) * uniforms.sharpness);
        totalAO += ssaoTex.sample(s, sampleUV).r * half(weight);
        totalWeight += weight;
    }

    return (totalWeight > 0.0) ? (totalAO / half(totalWeight)) : 1.0h;
}
