float calculateShadow(
    float4 shadowCoord, depth2d<float> shadowTex, ShadowData data, sampler shadowSampler) {
    // Perspective shadow (SpotLight): fragments behind the camera have w <= 0
    if (shadowCoord.w <= 0.0) return 1.0;

    shadowCoord.xyz /= shadowCoord.w;

    // Early-exit outside shadow frustum — avoids running PCF on the majority of pixels
    // that are outside the spotlight cone or directional shadow volume.
    const float3 v = abs(shadowCoord.xyz) - 1.0;
    if (max(max(v.x, v.y), v.z) > 0.0) return 1.0;

    shadowCoord.y *= -1.0;
    shadowCoord.xy = 0.5 + shadowCoord.xy * 0.5;

    shadowCoord.z += data.parameters.y;
    const float radius = data.parameters.w + 0.5;
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

    return clamp(mix(1.0, shadow / samples, data.parameters.x), 0.0, 1.0);
}
