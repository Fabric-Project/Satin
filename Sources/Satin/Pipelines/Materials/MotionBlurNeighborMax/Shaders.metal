// After the jump flood: across each tile's 3x3 neighborhood, the pointer whose mover has the
// longest motion. The blur reads the mover's velocity through it.
fragment float4 motionBlurNeighborMaxFragment(
    VertexData in [[stage_in]],
    texture2d<float, access::sample> tileMaxTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> jumpFloodTex [[texture(FragmentTextureCustom1)]]) {

    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);
    const float2 tileCount = float2(tileMaxTex.get_width(), tileMaxTex.get_height());
    const float2 pixelScale = tileCount;
    const float2 here = in.position.xy / tileCount;

    float2 best = here;
    float bestLengthSquared = -1.0f;
    for (int offsetY = -1; offsetY <= 1; offsetY++) {
        for (int offsetX = -1; offsetX <= 1; offsetX++) {
            const float2 checkUV = here + float2(offsetX, offsetY) / tileCount;
            if (any(checkUV < 0.0f) || any(checkUV > 1.0f)) { continue; }
            const float2 pointer = jumpFloodTex.sample(nearestSampler, checkUV).xy;
            const float2 motion = tileMaxTex.sample(nearestSampler, pointer).xy * pixelScale;
            const float lengthSquared = dot(motion, motion);
            if (lengthSquared > bestLengthSquared) {
                bestLengthSquared = lengthSquared;
                best = pointer;
            }
        }
    }
    return float4(best, 0.0f, 1.0f);
}
