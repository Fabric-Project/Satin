#ifndef SATIN_ALPHA_OIT_INCLUDED
#define SATIN_ALPHA_OIT_INCLUDED

#include <metal_stdlib>
using namespace metal;

// Custom SourceMaterial shaders can opt into Satin's Apple image-block alpha OIT path by:
// 1. defining `SATIN_ALPHA_OIT_ENABLED`
// 2. including `../../Includes/FragmentOutput.metal`
// 3. returning `FragmentOutput` via `buildColorFragmentOutput(...)`
// Shaders that do not opt in stay on classic hardware alpha blending.

struct AlphaOitFragmentValues
{
    half4 frontColor [[raster_order_group(0)]];  // exact nearest fragment (premultiplied); empty when frontDepth == INFINITY
    half  frontDepth [[raster_order_group(0)]];  // depth key [0=near, 1=far]; INFINITY when no front layer yet
    half4 accumColor [[raster_order_group(0)]];  // WBOIT: sum of (premultColor × weight)
    half  accumAlpha [[raster_order_group(0)]];  // WBOIT: sum of weights
    half  revealage  [[raster_order_group(0)]];  // WBOIT: product of (1 − alpha) across all accumulated fragments
};

struct AlphaOitFragmentStore
{
    AlphaOitFragmentValues values [[imageblock_data]];
};

#ifdef ALPHA_OIT
#define SATIN_ALPHA_OIT_FRAGMENT_DATA , AlphaOitFragmentValues alphaOitFragmentValues [[imageblock_data]]
#define SATIN_ALPHA_OIT_FORWARD_ARGS  , in.position, alphaOitFragmentValues
#else
#define SATIN_ALPHA_OIT_FRAGMENT_DATA
#define SATIN_ALPHA_OIT_FORWARD_ARGS
#endif

// McGuire & Bavoil 2013 weight function. depth in [0=near, 1=far].
// The denominators (5.0, 200.0) set the depth-sensitivity scale — halve them for
// scenes where all geometry sits in the near 10% of the depth range.
inline half wboit_weight(half depth, half alpha) {
    return alpha * max(1e-2h, min(3e3h,
        10.0h / (1e-5h + pow(depth / 5.0h, 2.0h) + pow(depth / 200.0h, 4.0h))
    ));
}

inline AlphaOitFragmentStore buildAlphaOitFragmentOutput(
    half4 color,
    float4 position,
    AlphaOitFragmentValues v
) {
    AlphaOitFragmentStore out;
    // Invert reversed-Z NDC depth (near=1, far=0) to a standard sort key (near=0, far=1).
    half depth = 1.0h - half(position.z / position.w);
    half4 pre = half4(color.rgb * color.a, color.a);

    if (depth <= v.frontDepth) {
        // Incoming fragment is closer: fold the current front into WBOIT, promote incoming.
        if (v.frontDepth < half(INFINITY)) {
            half w = wboit_weight(v.frontDepth, v.frontColor.a);
            v.accumColor += v.frontColor * w;
            v.accumAlpha += w;
            v.revealage  *= (1.0h - v.frontColor.a);
        }
        v.frontColor = pre;
        v.frontDepth = depth;
    } else {
        // Behind the front layer: accumulate into WBOIT.
        half w = wboit_weight(depth, color.a);
        v.accumColor += pre * w;
        v.accumAlpha += w;
        v.revealage  *= (1.0h - color.a);
    }

    out.values = v;
    return out;
}

#endif
