typedef struct {
    float intensity; // slider,0.0,2.0,1.0, Intensity
} SsaoCompositeUniforms;

fragment float4 ssaoCompositeFragment(
    VertexData in [[stage_in]],
    constant SsaoCompositeUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> aoTex [[texture(FragmentTextureCustom1)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float4 color = colorTex.sample(s, uv);
    const float ao = aoTex.sample(s, uv).r;
    const float occlusion = mix(1.0, ao, uniforms.intensity);

    return float4(color.rgb * occlusion, color.a);
}
