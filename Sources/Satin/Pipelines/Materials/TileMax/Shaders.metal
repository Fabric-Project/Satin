constant int kTileMaxRadius = 8;

fragment half2 tileMaxFragment(
    VertexData in [[stage_in]],
    texture2d<float, access::read> velocityTex [[texture(FragmentTextureCustom0)]]) {

    const uint2 coord = min(uint2(in.position.xy), uint2(velocityTex.get_width() - 1, velocityTex.get_height() - 1));
    const int2 sampleCoord = int2(coord);
    const int width = int(velocityTex.get_width());

    float2 bestVelocity = float2(0.0f);
    float bestMagnitudeSquared = 0.0f;

    for (int x = -kTileMaxRadius; x <= kTileMaxRadius; x++) {
        const uint sampleX = uint(clamp(sampleCoord.x + x, 0, width - 1));
        const float2 velocity = velocityTex.read(uint2(sampleX, coord.y)).rg;
        const float magnitudeSquared = dot(velocity, velocity);
        if (magnitudeSquared > bestMagnitudeSquared) {
            bestVelocity = velocity;
            bestMagnitudeSquared = magnitudeSquared;
        }
    }

    return half2(bestVelocity);
}
