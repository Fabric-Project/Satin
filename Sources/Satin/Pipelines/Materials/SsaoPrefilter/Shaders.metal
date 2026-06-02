#include "Library/ScreenSpace/ScreenSpaceUtilities.metal"

typedef struct {
    float4x4 inverseProjectionMatrix;
} SsaoPrefilterUniforms;

fragment half ssaoPrefilterFragment(
    VertexData in [[stage_in]],
    constant SsaoPrefilterUniforms &uniforms [[buffer(FragmentBufferCustom0)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom0)]]
) {
    constexpr sampler depthSampler(filter::nearest, address::clamp_to_edge);

    const float depth = depthTex.sample(depthSampler, in.texcoord);
    if (depth <= 0.0) {
        return 0.0h;
    }

    const float3 viewPosition = satinReconstructViewPosition(
        in.texcoord,
        depth,
        uniforms.inverseProjectionMatrix
    );
    return half(max(-viewPosition.z, 0.0));
}
