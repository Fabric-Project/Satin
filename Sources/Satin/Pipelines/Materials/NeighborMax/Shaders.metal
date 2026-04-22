fragment half2 neighborMaxFragment(
    VertexData in [[stage_in]],
    texture2d<float, access::read> tileMaxTex [[texture(FragmentTextureCustom0)]]) {

    const uint2 coord = min(uint2(in.position.xy), uint2(tileMaxTex.get_width() - 1, tileMaxTex.get_height() - 1));
    const int2 sampleCoord = int2(coord);
    const int height = int(tileMaxTex.get_height());

    float2 bestVelocity = float2(0.0f);
    float bestMagnitudeSquared = 0.0f;

    for (int y = -8; y <= 8; y++) {
        const uint sampleY = uint(clamp(sampleCoord.y + y, 0, height - 1));
        const float2 velocity = tileMaxTex.read(uint2(coord.x, sampleY)).rg;
        const float magnitudeSquared = dot(velocity, velocity);
        if (magnitudeSquared > bestMagnitudeSquared) {
            bestVelocity = velocity;
            bestMagnitudeSquared = magnitudeSquared;
        }
    }

    return half2(bestVelocity);
}
