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
    // position.z is already window-space depth in [0,1] (reversed-Z: near=1, far=0).
    // Invert to a sort key where near=0, far=1.
    half depth = 1.0h - half(position.z);
    half4 pre = half4(color.rgb * color.a, color.a);

    // Only fully-opaque fragments (alpha == 1.0 exactly) use the exact front layer. Any
    // fragment with alpha < 1.0 always goes into WBOIT so that intersecting transparent
    // surfaces blend continuously rather than producing a staircase, and so that gradients
    // approaching (but not reaching) 1.0 have no hard compositing break. The transition
    // from the last sub-1.0 half-float (~0.999) to 1.0 is one ULP — visually invisible.
    if (color.a >= 1.0h && depth <= v.frontDepth) {
        // Incoming near-opaque fragment is closer: fold the current front into WBOIT, promote incoming.
        if (v.frontDepth < half(INFINITY)) {
            half w = wboit_weight(v.frontDepth, v.frontColor.a);
            v.accumColor += v.frontColor * w;
            v.accumAlpha += w;
            v.revealage  *= (1.0h - v.frontColor.a);
        }
        v.frontColor = pre;
        v.frontDepth = depth;
    } else {
        // Any fragment with alpha < 1.0, or a fully-opaque fragment behind the front layer.
        half w = wboit_weight(depth, color.a);
        v.accumColor += pre * w;
        v.accumAlpha += w;
        v.revealage  *= (1.0h - color.a);
    }

    out.values = v;
    return out;
}

#endif
