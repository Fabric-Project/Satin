typedef struct {
    float4x4 projectionMatrix;
    float4x4 inverseProjectionMatrix;
    float4x4 viewMatrix;
    float radius;       // slider,0.01,2.0,0.5, Radius
    float bias;         // slider,0.0,0.1,0.025, Bias
    float power;        // slider,0.5,8.0,1.5, Power
    float contrast;     // slider,0.0,4.0,1.0, Contrast
    int kernelSize;     // slider,1,16,16, Kernel Size
    int noiseMode;      // slider,0,1,0, Noise Mode
    int rejectOffscreenSamples; // slider,0,1,1, Reject Offscreen Samples
} SsaoUniforms;

// Hemisphere kernel with quadratic distance distribution — biases samples
// closer to the fragment for better near-surface occlusion sensitivity.
// All z values are strictly positive (upper hemisphere only).
static constant float3 ssaoKernel[16] = {
    float3( 0.0308,  0.0000,  0.0308),
    float3(-0.0655,  0.0000,  0.0655),
    float3( 0.0414,  0.0414,  0.0828),
    float3(-0.1237,  0.0000,  0.1237),
    float3( 0.1615,  0.0000,  0.0808),
    float3(-0.0742,  0.0742,  0.1485),
    float3( 0.2121,  0.0000,  0.2121),
    float3(-0.1875,  0.1875,  0.1875),
    float3( 0.1061,  0.1061,  0.3182),
    float3(-0.2357,  0.0000,  0.2357),
    float3( 0.3250,  0.0000,  0.1625),
    float3(-0.2449,  0.2449,  0.2449),
    float3( 0.1155,  0.2309,  0.4619),
    float3(-0.3248,  0.0000,  0.3248),
    float3( 0.3536,  0.0000,  0.3536),
    float3(-0.3464,  0.3464,  0.1000),
};

// 4x4 tileable noise grid for per-pixel kernel rotation — avoids the
// diagonal banding produced by Halton sequences at large pixel indices.
static constant float3 ssaoNoise[16] = {
    float3( 0.8973, -0.4428, 0.0), float3(-0.2113,  0.9747, 0.0),
    float3( 0.5234, -0.8519, 0.0), float3(-0.9634,  0.2683, 0.0),
    float3( 0.1452,  0.9894, 0.0), float3(-0.7123, -0.7019, 0.0),
    float3( 0.9812,  0.1933, 0.0), float3(-0.3456,  0.9384, 0.0),
    float3( 0.6712, -0.7412, 0.0), float3(-0.8934,  0.4492, 0.0),
    float3( 0.2819,  0.9594, 0.0), float3(-0.5634, -0.8262, 0.0),
    float3( 0.9421, -0.3353, 0.0), float3(-0.1876,  0.9823, 0.0),
    float3( 0.7234, -0.6904, 0.0), float3(-0.4523,  0.8918, 0.0),
};

static float3 ssaoReconstructViewPos(float2 uv, float depth, float4x4 invProj) {
    // Satin UV has y=0 at top; Metal clip space has y=+1 at top, so flip Y.
    const float4 clipPos = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    float4 viewPos = invProj * clipPos;
    return viewPos.xyz / viewPos.w;
}

static bool ssaoUvInside(float2 uv) {
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

fragment half ssaoFragment(
    VertexData in [[stage_in]],
    constant SsaoUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> normalTex [[texture(FragmentTextureCustom1)]]) {

    constexpr sampler s(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;

    const float depth = depthTex.sample(s, uv);
    // Reversed-Z: background is cleared to 0.0 (far plane), not 1.0.
    if (depth <= 0.0) return 1.0h;

    const float3 fragViewPos = ssaoReconstructViewPos(uv, depth, uniforms.inverseProjectionMatrix);

    // MRT normals are packed from [-1, 1] into [0, 1].
    const float3 worldNormal = normalTex.sample(s, uv).xyz * 2.0 - 1.0;
    if (dot(worldNormal, worldNormal) < 1e-6) return 1.0h;
    const float3 normal = normalize((uniforms.viewMatrix * float4(worldNormal, 0.0)).xyz);

    // `[[position]]` is in render-target pixel space in the fragment stage, which keeps the
    // kernel rotation anchored to the AO target instead of any interpolated clip coordinate.
    const uint2 pixelCoord = uint2(floor(in.position.xy));
    const uint noiseIndex = (pixelCoord.x & 3u) + ((pixelCoord.y & 3u) << 2u);
    const float3 randomVec = uniforms.noiseMode == 0
        ? ssaoNoise[noiseIndex]
        : float3(0.70710678, 0.70710678, 0.0);

    const float3 tangent   = normalize(randomVec - normal * dot(randomVec, normal));
    const float3 bitangent = cross(normal, tangent);
    const float3x3 TBN     = float3x3(tangent, bitangent, normal);

    const int kernelSize = clamp(uniforms.kernelSize, 1, 16);
    const float radius = uniforms.radius;
    const float bias = uniforms.bias;

    float occlusion = 0.0;
    for (int i = 0; i < kernelSize; i++) {
        float3 samplePos = fragViewPos + TBN * ssaoKernel[i] * radius;

        float4 offset = uniforms.projectionMatrix * float4(samplePos, 1.0);
        offset.xyz /= offset.w;
        // NDC y=+1 is top; Satin UV y=0 is top, so flip Y when converting to sample UV.
        const float2 sampleUV = float2(offset.x * 0.5 + 0.5, 0.5 - offset.y * 0.5);
        if (uniforms.rejectOffscreenSamples != 0 && !ssaoUvInside(sampleUV)) {
            continue;
        }

        const float sampleDepth = depthTex.sample(s, sampleUV);
        if (sampleDepth <= 0.0) {
            continue;
        }
        const float3 sampleViewPos = ssaoReconstructViewPos(sampleUV, sampleDepth, uniforms.inverseProjectionMatrix);

        const float rangeCheck = smoothstep(0.0, 1.0, radius / abs(fragViewPos.z - sampleViewPos.z + 1e-5));
        // Reversed-Z reconstruction yields more negative view-space z values as geometry moves
        // farther from the camera, so a fetched depth occludes only when it lies in front of
        // the candidate sample point after applying the bias.
        occlusion += (sampleViewPos.z >= samplePos.z + bias ? 1.0 : 0.0) * rangeCheck;
    }

    float ao = 1.0 - occlusion / float(kernelSize);
    ao = pow(ao, uniforms.power);
    ao = saturate(uniforms.contrast * (ao - 0.5) + 0.5);
    return half(ao);
}
