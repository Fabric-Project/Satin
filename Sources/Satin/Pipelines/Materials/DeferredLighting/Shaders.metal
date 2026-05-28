#include "Satin/PbrConstants.metal"

#include "Library/Pbr/Pbr.metal"
#include "Library/SafeNormalize.metal"

typedef struct {
    float4x4 inverseProjectionMatrix;
    float4x4 inverseViewMatrix;
    float4x4 reflectionTexcoordTransform;
    float4x4 irradianceTexcoordTransform;
    float4 worldCameraPosition;
    float environmentIntensity;          // slider,0.0,4.0,1.0
    float gammaCorrection;               // slider,0.0,1.0,1.0
    float specular;                      // slider,0.0,1.0,0.5
    float deferredLightingPadding;
} DeferredLightingUniforms;

static float3 deferredLightingReconstructViewPosition(
    float2 uv,
    float depth,
    float4x4 inverseProjectionMatrix
) {
    // Satin UV has y=0 at top; Metal clip space has y=+1 at top, so flip Y.
    const float4 clipPosition = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    const float4 viewPosition = inverseProjectionMatrix * clipPosition;
    return viewPosition.xyz / viewPosition.w;
}

fragment half4 deferredLightingFragment(
    VertexData in [[stage_in]],
    // inject lighting args
#if defined(PROJECTOR_COUNT)
    constant float4x4 *projectorMatrices [[buffer(FragmentBufferProjectorMatrices)]],
    constant float4x4 *projectorTransforms [[buffer(FragmentBufferProjectorTransforms)]],
    array<texture2d<float>, PROJECTOR_COUNT> projectorTextures [[texture(FragmentTextureProjector0)]],
#endif
#if defined(DIRECT_SHADOW_COUNT) && defined(DIRECT_SHADOW_TEXTURE_COUNT)
    constant ShadowData *directShadows [[buffer(FragmentBufferDirectShadows)]],
    constant float4x4 *directShadowMatrices [[buffer(FragmentBufferDirectShadowMatrices)]],
    array<depth2d<float>, DIRECT_SHADOW_TEXTURE_COUNT> directShadowTextures [[texture(FragmentTextureDirectShadow0)]],
#endif
    constant DeferredLightingUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> albedoTexture [[texture(FragmentTextureCustom0)]],
    texture2d<float, access::sample> normalTexture [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> pbrTexture [[texture(FragmentTextureCustom2)]],
    texture2d<float, access::sample> emissiveTexture [[texture(FragmentTextureCustom3)]],
    depth2d<float, access::sample> depthTexture [[texture(FragmentTextureCustom4)]],
    texturecube<float> reflectionMap [[texture(PBRTextureReflection)]],
    texturecube<float> irradianceMap [[texture(PBRTextureIrradiance)]],
    texture2d<float> brdfMap [[texture(PBRTextureBrdf)]]
) {
    constexpr sampler gbufferSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float4 albedoSample = albedoTexture.sample(gbufferSampler, uv);
    const float depth = depthTexture.sample(gbufferSampler, uv);
    if (depth >= 1.0) {
        discard_fragment();
    }

    const float3 viewPosition = deferredLightingReconstructViewPosition(
        uv,
        depth,
        uniforms.inverseProjectionMatrix
    );
    const float3 worldPosition = (uniforms.inverseViewMatrix * float4(viewPosition, 1.0)).xyz;

    float3 worldNormal = normalTexture.sample(gbufferSampler, uv).xyz * 2.0 - 1.0;
    // If the stored normal is invalid, fall back to a finite geometric reconstruction.
    const float3 geometricNormal = safeNormalize(cross(dfdx(worldPosition), dfdy(worldPosition)), float3(0.0f, 0.0f, 1.0f));
    const float worldNormalLength2 = dot(worldNormal, worldNormal);
    if (!isfinite(worldNormalLength2) || worldNormalLength2 <= 1.0e-4) {
        worldNormal = geometricNormal;
    } else {
        worldNormal = safeNormalize(worldNormal, geometricNormal);
    }

    PixelInfo pixel;
    pixel.position = worldPosition;
    pixel.view = normalize(uniforms.worldCameraPosition.xyz - worldPosition);
    if (dot(worldNormal, pixel.view) < 0.0) {
        worldNormal *= -1.0;
    }
    pixel.normal = worldNormal;
    pixel.tangent = float3(1.0, 0.0, 0.0);
    pixel.bitangent = float3(0.0, 1.0, 0.0);

    const float4 pbrSample = pbrTexture.sample(gbufferSampler, uv);
    const bool hasPbrSample = pbrSample.a > 0.0;
    pixel.material.baseColor = albedoSample.rgb;
    pixel.material.emissiveColor = emissiveTexture.sample(gbufferSampler, uv).rgb;
    pixel.material.occlusion = hasPbrSample ? pbrSample.b : 1.0;
    pixel.material.metallic = hasPbrSample ? pbrSample.g : 0.0;
    pixel.material.roughness = max(0.045, hasPbrSample ? pbrSample.r : 1.0);
    pixel.material.specular = uniforms.specular;
    pixel.material.environmentIntensity = uniforms.environmentIntensity;
    pixel.material.gammaCorrection = uniforms.gammaCorrection;
    pixel.material.alpha = 1.0;
    pixel.material.reflectionTexcoordTransform = uniforms.reflectionTexcoordTransform;
    pixel.material.irradianceTexcoordTransform = uniforms.irradianceTexcoordTransform;
    pixel.radiance = pixel.material.emissiveColor;

#include "Chunks/PbrDirectLighting.metal"
#include "Chunks/PbrInDirectLighting.metal"

    return half4(half3(pbrTonemap(pixel)), half(pixel.material.alpha));
}
