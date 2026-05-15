#ifndef SATIN_ALPHA_OIT_INCLUDED
#define SATIN_ALPHA_OIT_INCLUDED

#include <metal_stdlib>
using namespace metal;

// Custom SourceMaterial shaders can opt into Satin's Apple image-block alpha OIT path by:
// 1. defining `SATIN_ALPHA_OIT_ENABLED`
// 2. including `../../Includes/FragmentOutput.metal`
// 3. returning `FragmentOutput` via `buildColorFragmentOutput(...)`
// Shaders that do not opt in stay on classic hardware alpha blending.

static constexpr constant short kAlphaOitLayerCount = 4;

struct AlphaOitFragmentValues
{
    half4 colors [[raster_order_group(0)]] [kAlphaOitLayerCount];
    half depths [[raster_order_group(0)]] [kAlphaOitLayerCount];
};

struct AlphaOitFragmentStore
{
    AlphaOitFragmentValues values [[imageblock_data]];
};

#ifdef ALPHA_OIT
#define SATIN_ALPHA_OIT_FRAGMENT_DATA , AlphaOitFragmentValues alphaOitFragmentValues [[imageblock_data]]
#define SATIN_ALPHA_OIT_FORWARD_ARGS , in.position, alphaOitFragmentValues
#else
#define SATIN_ALPHA_OIT_FRAGMENT_DATA
#define SATIN_ALPHA_OIT_FORWARD_ARGS
#endif

inline AlphaOitFragmentStore buildAlphaOitFragmentOutput(
    half4 color,
    float4 position,
    AlphaOitFragmentValues fragmentValues
) {
    AlphaOitFragmentStore out;
    half4 layerColor = color;
    //layerColor.rgb *= layerColor.a;
    // Invert reversed-Z NDC depth (near=1, far=0) to a standard sort key (near=0, far=1).
    half depth = 1.0h - half(position.z / position.w);

    for (short i = 0; i < kAlphaOitLayerCount; ++i) {
        half existingDepth = fragmentValues.depths[i];
        half4 existingColor = fragmentValues.colors[i];
        bool insert = depth <= existingDepth;

        fragmentValues.colors[i] = insert ? layerColor : existingColor;
        fragmentValues.depths[i] = insert ? depth : existingDepth;

        layerColor = insert ? existingColor : layerColor;
        depth = insert ? existingDepth : depth;
    }

    out.values = fragmentValues;
    return out;
}

#endif
