typedef struct {
    int tileSize;
} MotionBlurTileMaxUniforms;

// One texel per tile: the longest velocity in the tile (UV units, full frame, current minus
// previous) and the depth where it was found, so the jump-flood dilation can prefer the
// front-most mover. After sphynx-owner's JFA-driven motion blur (MIT).
fragment float4 motionBlurTileMaxFragment(
    VertexData in [[stage_in]],
    constant MotionBlurTileMaxUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::read> velocityTex [[texture(FragmentTextureCustom0)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom1)]]) {

    constexpr sampler depthSampler(filter::nearest, address::clamp_to_edge);
    const uint tileSize = uint(max(uniforms.tileSize, 1));
    const uint2 size = uint2(velocityTex.get_width(), velocityTex.get_height());
    const float2 pixelScale = float2(size);
    const uint2 origin = uint2(in.position.xy) * tileSize;

    float2 longest = float2(0.0f);
    uint2 longestCoord = origin;
    float longestLengthSquared = -1.0f;
    for (uint y = 0; y < tileSize; y++) {
        for (uint x = 0; x < tileSize; x++) {
            const uint2 coord = origin + uint2(x, y);
            if (coord.x >= size.x || coord.y >= size.y) { continue; }
            const float2 velocity = velocityTex.read(coord).rg;
            const float2 inPixels = velocity * pixelScale;
            const float lengthSquared = dot(inPixels, inPixels);
            if (lengthSquared > longestLengthSquared) {
                longestLengthSquared = lengthSquared;
                longest = velocity;
                longestCoord = coord;
            }
        }
    }
    const float depth = depthTex.sample(depthSampler, (float2(min(longestCoord, size - 1)) + 0.5f) / pixelScale);
    return float4(longest, 0.0f, depth);
}
