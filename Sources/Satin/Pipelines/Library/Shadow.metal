float calculateShadow(
    float4 shadowCoord, depth2d<float> shadowTex, ShadowData data, sampler shadowSampler) {
    shadowCoord.xyz /= shadowCoord.w;

    // SDF Box Calculation to see if we are within the shadow frustrum
    const float3 v = abs(shadowCoord.xyz) - 1.0;
    const float inFrustum = step(max(max(v.x, v.y), v.z), 0.0);

    shadowCoord.y *= -1.0;
    shadowCoord.xy = 0.5 + shadowCoord.xy * 0.5;

    shadowCoord.z += data.bias;
    const float radius = data.radius + 0.5;
    const float2 texelSize = 1.0 / float2(shadowTex.get_width(), shadowTex.get_height());
    float shadow = 0.0;
    float samples = 0.0;
    for (float y = -radius; y <= radius; y += 1.0) {
        for (float x = -radius; x <= radius; x += 1.0) {
            shadow += shadowTex.sample_compare(
                shadowSampler, shadowCoord.xy + float2(x, y) * texelSize, shadowCoord.z);
            samples += 1.0;
        }
    }

    return mix(1.0, (shadow / samples), data.strength * inFrustum);
}
