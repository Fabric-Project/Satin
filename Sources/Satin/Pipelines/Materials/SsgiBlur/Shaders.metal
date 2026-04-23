typedef struct {
    float blurStrength;     // slider,0.0,1.0,0.65
    float depthSharpness;   // slider,1.0,2000.0,500.0
    float normalSharpness;  // slider,1.0,128.0,32.0
} SsgiBlurUniforms;

typedef struct {
    float2 direction;
} SsgiBlurPassUniforms;

fragment float4 ssgiBlurFragment(
    VertexData in [[stage_in]],
    constant SsgiBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    constant SsgiBlurPassUniforms &passUniforms [[buffer(FragmentBufferCustom0)]],
    texture2d<float, access::sample> ssgiTex [[texture(FragmentTextureCustom0)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom2)]]
) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float centerDepth = depthTex.sample(s, uv);
    if (centerDepth <= 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    const float3 centerNormal = normalize(normalTex.sample(s, uv).xyz * 2.0 - 1.0);
    const int radius = int(round(clamp(uniforms.blurStrength, 0.0, 1.0) * 8.0));
    if (radius <= 0) {
        return ssgiTex.sample(s, uv);
    }

    const float2 texelSize = 1.0 / float2(ssgiTex.get_width(), ssgiTex.get_height());
    const float2 sampleStep = passUniforms.direction * texelSize;

    float4 total = 0.0;
    float totalWeight = 0.0;

    for (int i = -radius; i <= radius; i++) {
        const float2 sampleUV = uv + sampleStep * float(i);
        const float sampleDepth = depthTex.sample(s, sampleUV);
        if (sampleDepth <= 0.0) {
            continue;
        }

        const float3 sampleNormal = normalize(normalTex.sample(s, sampleUV).xyz * 2.0 - 1.0);
        const float depthWeight = exp(-abs(centerDepth - sampleDepth) * uniforms.depthSharpness);
        const float normalWeight = pow(max(dot(centerNormal, sampleNormal), 0.0), uniforms.normalSharpness);
        const float spatialWeight = 1.0 - (abs(float(i)) / float(radius + 1));
        const float weight = max(depthWeight * normalWeight * spatialWeight, 1.0e-4);

        total += ssgiTex.sample(s, sampleUV) * weight;
        totalWeight += weight;
    }

    if (totalWeight <= 0.0) {
        return ssgiTex.sample(s, uv);
    }

    return total / totalWeight;
}
