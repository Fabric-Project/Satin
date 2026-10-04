typedef struct {
    float shutterAngle; // slider,0,2880,180
    int samples;        // slider,1,32,16
    float jitter;       // slider,0,1,1
    int frame;
    float maxBlurRadius;
} MotionBlurUniforms;
constant float kMaxShutterAngle = 2880.0f;

// Jump-flood-driven motion blur, after sphynx-owner's "JFA driven motion blur" (MIT), which
// builds on McGuire 2012 and Guertin 2014.
//
// The blur is retrospective: during the shutter a surface moved from its previous position
// to where it is now, so each pixel looks ahead along motion (toward where things are now)
// for what passed over it. Velocities are current minus previous, in UV units per frame.
//
// Two estimates are blended by coverage:
// - trail: things that swept over this pixel, found along the dilated mover's motion. A
//   sample counts when its own motion reaches back to here and it is not behind this pixel.
// - own: this pixel's own surface smeared along its motion, revealing whatever is behind it
//   where it has moved on. This is what erodes a moving silhouette instead of leaving it
//   crisp.

// PCG4D hash — animates blue noise sample position per frame
static void pcg4d(thread uint4& v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w; v.y += v.z * v.x;
    v.z += v.x * v.y; v.w += v.y * v.z;
    v ^= v >> 16u;
    v.x += v.y * v.w; v.y += v.z * v.x;
    v.z += v.x * v.y; v.w += v.y * v.z;
}

// Distance along the view, up to scale, from Satin's reverse-Z depth (about near / distance).
// Cleared background (depth 0) becomes effectively infinite.
static float viewDistance(float reverseDepth) {
    return 1.0f / max(reverseDepth, 1e-6f);
}

// 1 when `a` is nearer than `b` or level with it, falling to 0 as `a` gets farther, relative
// to the nearer of the two (McGuire 2012, scale-free form).
static float nearerOrLevel(float distanceA, float distanceB) {
    return clamp(1.0f - (distanceA - distanceB) / min(distanceA, distanceB), 0.0f, 1.0f);
}

/// A stored velocity as pixels moved during this shutter, clamped to `maximumLength`.
static float2 shutterVelocityInPixels(float2 storedVelocity, float shutterFraction, float2 pixelScale, float maximumLength) {
    const float2 velocity = storedVelocity * shutterFraction * pixelScale;
    return velocity / max(1.0f, length(velocity) / max(maximumLength, 1e-6f));
}

fragment half4 motionBlurFragment(
    VertexData in [[stage_in]],
    constant MotionBlurUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> velocityTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::read> blueNoiseTex [[texture(FragmentTextureCustom2)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom3)]],
    texture2d<float, access::sample> neighborMaxTex [[texture(FragmentTextureCustom4)]],
    texture2d<float, access::sample> tileMaxTex [[texture(FragmentTextureCustom5)]]) {

    constexpr sampler colorSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

    const float2 x = in.texcoord;
    const float4 colorX = colorTex.sample(colorSampler, x);

    const float shutterFraction = clamp(uniforms.shutterAngle, 0.0f, kMaxShutterAngle) / 360.0f;
    if (shutterFraction <= 1e-6f) {
        return half4(colorX);
    }

    const float2 pixelScale = float2(velocityTex.get_width(), velocityTex.get_height());
    const float maxRadius = uniforms.maxBlurRadius;

    // Blue noise, animated per frame, jitters the tile lookup and the sample positions.
    const uint frame = uint(uniforms.frame);
    uint4 seed = uint4(frame, frame * 15843u, frame * 31u + 4566u, frame * 2345u + 58585u);
    pcg4d(seed);
    const uint2 noiseCoord = (uint2(in.position.xy) + seed.xy) % uint2(blueNoiseTex.get_width(), blueNoiseTex.get_height());
    const float noise = blueNoiseTex.read(noiseCoord).r;

    // The mover dilated over this pixel, read through the neighbor-max pointer. Jittering the
    // lookup by a quarter tile in a random direction hides the tile grid.
    const float angle = noise * 2.0f * M_PI_F;
    const float2 tileCount = float2(neighborMaxTex.get_width(), neighborMaxTex.get_height());
    const float2 tileJitter = float2(cos(angle), sin(angle)) / tileCount * 0.25f * uniforms.jitter;
    const float2 moverPointer = neighborMaxTex.sample(nearestSampler, x + tileJitter).xy;
    const float2 vn = shutterVelocityInPixels(tileMaxTex.sample(nearestSampler, moverPointer).xy, shutterFraction, pixelScale, maxRadius);
    const float vnLength = length(vn);
    if (vnLength <= 0.5f) {
        return half4(colorX);
    }
    const float2 wn = vn / vnLength;

    const float2 vx = shutterVelocityInPixels(velocityTex.sample(nearestSampler, x).rg, shutterFraction, pixelScale, maxRadius);
    const float zx = viewDistance(depthTex.sample(nearestSampler, x));
    const float j = (noise - 0.5f) * uniforms.jitter;

    float trailWeight = 1e-5f;
    float4 trailSum = colorX * trailWeight;
    float ownWeight = 1e-5f;
    float4 ownSum = colorX * ownWeight;

    const int sampleCount = clamp(uniforms.samples, 1, 64);
    for (int i = 0; i < sampleCount; i++) {
        // Fraction of the way along the motion, toward where things are now.
        const float s = (float(i) + j + 1.0f) / (float(sampleCount) + 1.0f);

        // Own: this pixel's surface along its own motion. Keep it where the sample is in
        // front; elsewhere take the sample, which smears the surface and reveals what is
        // behind it once it has moved on.
        const float2 ownY = x + vx / pixelScale * s;
        const float revealed = nearerOrLevel(zx, viewDistance(depthTex.sample(nearestSampler, ownY)));
        ownSum += mix(colorX, colorTex.sample(colorSampler, ownY), revealed);
        ownWeight += 1.0f;

        // Trail: a sample along the mover's motion counts when its own motion, pointed the
        // same way, reaches back to this pixel, and it is not behind this pixel.
        const float T = s * vnLength;
        const float2 y = x + vn / pixelScale * s;
        const float2 vy = shutterVelocityInPixels(velocityTex.sample(nearestSampler, y).rg, shutterFraction, pixelScale, maxRadius);
        const float vyLength = max(0.5f, length(vy));
        const float inFront = nearerOrLevel(viewDistance(depthTex.sample(nearestSampler, y)), zx);
        const float alignment = max(0.0f, dot(vy / vyLength, wn));
        const float reaches = step(T, vyLength * alignment);
        const float inside = (all(y >= 0.0f) && all(y <= 1.0f)) ? 1.0f : 0.0f;
        const float trail = inFront * reaches * inside;
        trailWeight += trail;
        trailSum += colorTex.sample(colorSampler, y) * trail;
    }

    // The share of samples that found a trail is the share of the shutter this pixel spent
    // covered by something passing over it.
    const float4 trail = trailSum / trailWeight;
    const float4 own = ownSum / ownWeight;
    const float coverage = clamp(trailWeight / float(sampleCount), 0.0f, 1.0f);
    return half4(mix(own, trail, coverage));
}
