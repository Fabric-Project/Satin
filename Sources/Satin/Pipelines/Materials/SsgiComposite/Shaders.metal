typedef struct {
    float giIntensity; // slider,0.0,4.0,1.0
    float aoIntensity; // slider,0.0,1.0,0.35
    float aoLift;      // slider,0.0,1.0,0.2
} SsgiCompositeUniforms;

fragment float4 ssgiCompositeFragment(
    VertexData in [[stage_in]],
    constant SsgiCompositeUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> ssgiTex [[texture(FragmentTextureCustom1)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float4 color = colorTex.sample(s, uv);
    const float4 ssgi = ssgiTex.sample(s, uv);
    const float visibility = saturate(max(ssgi.a, uniforms.aoLift));
    const float aoIntensity = max(uniforms.aoIntensity, 0.0);
    const float occlusion = aoIntensity > 0.0 ? pow(visibility, aoIntensity) : 1.0;

    return float4(color.rgb * occlusion + ssgi.rgb * uniforms.giIntensity, color.a);
}
