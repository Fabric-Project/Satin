typedef struct {
    int stepSize;
    int isFirstPass;
    float shutterFraction;
    float perpendicularTolerance;
} MotionBlurJumpFloodUniforms;

// One jump-flood pass of velocity dilation (sphynx-owner, "Using the Jump Flood Algorithm to
// Dilate Velocity Maps", MIT). Each tile keeps a pointer (UV) to the tile whose motion trail
// covers it: the tile lies behind that mover along its motion, within the shutter's reach
// and close to its line. Among candidates the front-most wins. Passes run with step sizes
// shrinking by 3 (for example 9, 3, 1 tiles), so a tile finds movers up to
// (3^passes - 1) / 2 tiles away in log time, whatever direction they move in.
fragment float4 motionBlurJumpFloodFragment(
    VertexData in [[stage_in]],
    constant MotionBlurJumpFloodUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> tileMaxTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> previousTex [[texture(FragmentTextureCustom1)]]) {

    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);
    const float2 tileCount = float2(tileMaxTex.get_width(), tileMaxTex.get_height());
    const float2 here = in.position.xy / tileCount;
    const float2 step = float(max(uniforms.stepSize, 1)) / tileCount;

    float bestScore = 0.0f;
    float2 chosen = here;
    for (int offsetY = -1; offsetY <= 1; offsetY++) {
        for (int offsetX = -1; offsetX <= 1; offsetX++) {
            const float2 checkUV = here + float2(offsetX, offsetY) * step;
            if (any(checkUV < 0.0f) || any(checkUV > 1.0f)) { continue; }
            // The first pass seeds each tile with itself; later passes follow earlier pointers.
            const float2 source = uniforms.isFirstPass != 0 ? checkUV : previousTex.sample(nearestSampler, checkUV).xy;
            const float4 mover = tileMaxTex.sample(nearestSampler, source);
            const float2 motion = mover.xy;
            const float motionLengthSquared = dot(motion, motion);
            // No motion, or no depth (cleared background): nothing to dilate.
            if (motionLengthSquared <= 1e-12f || mover.w <= 0.0f) { continue; }

            // Where this tile sits relative to the mover, in units of its motion: behind it
            // (the trail) between 0 and the shutter's reach, and near its line.
            const float2 offset = source - here;
            const float alongMotion = dot(motion, offset) / motionLengthSquared;
            const float acrossMotion = abs(motion.x * offset.y - motion.y * offset.x) / motionLengthSquared;
            const bool inReach = alongMotion >= 0.0f && alongMotion <= uniforms.shutterFraction;
            const bool nearLine = acrossMotion <= uniforms.perpendicularTolerance * uniforms.shutterFraction;
            if (!inReach || !nearLine) { continue; }

            // Reverse-Z: larger depth is nearer.
            if (mover.w > bestScore) {
                bestScore = mover.w;
                chosen = source;
            }
        }
    }
    return float4(chosen, 0.0f, 1.0f);
}
