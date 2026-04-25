typedef struct {
    int maxRadius;
} BokehDepthOfFieldNearMaxUniforms;

typedef struct {
    float2 direction;
} BokehDepthOfFieldNearMaxPassUniforms;

fragment half bokehDepthOfFieldNearMaxFragment(
    VertexData in [[stage_in]],
    constant BokehDepthOfFieldNearMaxUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    constant BokehDepthOfFieldNearMaxPassUniforms &passUniforms [[buffer(FragmentBufferCustom0)]],
    texture2d<half, access::sample> radiusTex [[texture(FragmentTextureCustom0)]]
) {
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

    const int radius = clamp(uniforms.maxRadius, 0, 24);
    if (radius == 0) {
        return radiusTex.sample(nearestSampler, in.texcoord).r;
    }

    const float2 texelSize = float2(
        1.0f / float(radiusTex.get_width()),
        1.0f / float(radiusTex.get_height())
    );
    const float2 step = passUniforms.direction * texelSize;

    half maxValue = 0.0h;
    for (int i = -24; i <= 24; ++i) {
        if (abs(i) > radius) { continue; }
        const float2 sampleUV = in.texcoord + step * float(i);
        maxValue = max(maxValue, radiusTex.sample(nearestSampler, sampleUV).r);
    }

    return maxValue;
}
