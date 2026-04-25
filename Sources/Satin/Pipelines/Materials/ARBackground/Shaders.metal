typedef struct {
    float4 color; // color
    bool srgb;    // toggle
} ARBackgroundUniforms;

static constexpr sampler s(mag_filter::linear, min_filter::linear);

fragment float4 arbackgroundFragment(
    VertexData in [[stage_in]],
    constant ARBackgroundUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> capturedImageTextureY [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> capturedImageTextureCbCr [[texture(FragmentTextureCustom1)]]) {
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f));

    float4 color = ycbcrToRGBTransform * float4(
                                             capturedImageTextureY.sample(s, in.texcoord).r,
                                             capturedImageTextureCbCr.sample(s, in.texcoord).rg,
                                             1.0);
    color.rgb = mix(color.rgb, pow(color.rgb, 2.2), float(uniforms.srgb));
    return uniforms.color * color;
}
