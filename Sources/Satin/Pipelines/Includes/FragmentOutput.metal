#include "SurfaceOutput.metal"
#include "../Library/SafeNormalize.metal"

// Builds a FragmentOutput from a SurfaceOutput and the already-computed lit color.
// Velocity is geometry-derived and computed here — materials never need to handle it.
// When OUTPUT_VELOCITY is active, the vertex function must output currentClipPos and
// previousClipPos (both float4, clip-space) in the vertex data struct.
inline FragmentOutput buildFragmentOutput(
    SurfaceOutput surface,
    half4 litColor
#ifdef OUTPUT_VELOCITY
    , float4 currentClipPos
    , float4 previousClipPos
#endif
#ifdef ALPHA_OIT
    , float4 position
    , AlphaOitFragmentValues alphaOitFragmentValues
#endif
) {
#ifdef ALPHA_OIT
    return buildAlphaOitFragmentOutput(litColor, position, alphaOitFragmentValues);
#else
    FragmentOutput out;
    out.color = litColor;

#ifdef OUTPUT_ALBEDO
    out.albedo   = half4(surface.albedo, 1.0h);
#endif

#ifdef OUTPUT_NORMALS
    // Encode world-space normal to [0,1] range for storage in rgba16Float.
    // This is the last boundary before an invalid normal reaches the G-buffer.
    const float3 safeSurfaceNormal = safeNormalize(float3(surface.normal), float3(0.0f, 0.0f, 1.0f));
    out.normal   = half4(half3(safeSurfaceNormal * 0.5h + 0.5h), 1.0h);
#endif

#ifdef OUTPUT_PBR
    // r=roughness, g=metalness, b=ao, a=unused
    out.pbr      = half4(surface.roughness, surface.metalness, surface.ao, 1.0h);
#endif

#ifdef OUTPUT_VELOCITY
    // NDC delta, Y-flipped to UV space (+V down). Matches the encoding in Velocity/Shaders.metal.
    float2 curr  = currentClipPos.xy  / currentClipPos.w;
    float2 prev  = previousClipPos.xy / previousClipPos.w;
    float2 delta = curr - prev;
    out.velocity = half2(delta.x * 0.5h, -delta.y * 0.5h);
#endif

#ifdef OUTPUT_EMISSIVE
    out.emissive = half4(surface.emissive, 1.0h);
#endif

    return out;
#endif
}

inline FragmentOutput buildColorFragmentOutput(
    half4 color
#ifdef ALPHA_OIT
    , float4 position
    , AlphaOitFragmentValues alphaOitFragmentValues
#endif
) {
#ifdef ALPHA_OIT
    return buildAlphaOitFragmentOutput(color, position, alphaOitFragmentValues);
#else
    FragmentOutput out;
    out.color = color;
    return out;
#endif
}
