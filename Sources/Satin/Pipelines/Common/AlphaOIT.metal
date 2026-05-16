#include <metal_stdlib>
using namespace metal;

struct AlphaOitFragmentValues
{
    half4 frontColor [[raster_order_group(0)]];
    half  frontDepth [[raster_order_group(0)]];
    half4 accumColor [[raster_order_group(0)]];
    half  accumAlpha [[raster_order_group(0)]];
    half  revealage  [[raster_order_group(0)]];
};

struct AlphaOitVertexData
{
    float4 position [[position]];
};

vertex AlphaOitVertexData alphaOitBlendVertex(uint vertexID [[vertex_id]]) {
    AlphaOitVertexData out;
    out.position.x = vertexID == 2 ? 3.0 : -1.0;
    out.position.y = vertexID == 0 ? -3.0 : 1.0;
    out.position.z = 0.0;
    out.position.w = 1.0;
    return out;
}

kernel void alphaOitClearTileData(
    imageblock<AlphaOitFragmentValues, imageblock_layout_explicit> blockData,
    ushort2 localThreadID [[thread_position_in_threadgroup]]
) {
    threadgroup_imageblock AlphaOitFragmentValues *v = blockData.data(localThreadID);
    v->frontColor = half4(0.0h);
    v->frontDepth = half(INFINITY);
    v->accumColor = half4(0.0h);
    v->accumAlpha = 0.0h;
    v->revealage  = 1.0h;
}

fragment half4 alphaOitBlendFragment(
    AlphaOitFragmentValues v [[imageblock_data]],
    half4 backgroundColor [[color(0), raster_order_group(0)]]
) {
    // Resolve WBOIT accumulator over the opaque background.
    half3 wboitColor = v.accumColor.rgb / max(v.accumAlpha, 1e-4h);
    half  wboitAlpha = 1.0h - v.revealage;
    half4 out;
    out.rgb = wboitColor * wboitAlpha + backgroundColor.rgb * v.revealage;
    out.a   = wboitAlpha + backgroundColor.a * v.revealage;

    // Composite the exact front layer on top (premultiplied over-blend).
    if (v.frontDepth < half(INFINITY)) {
        out.rgb = v.frontColor.rgb + (1.0h - v.frontColor.a) * out.rgb;
        out.a   = v.frontColor.a   + (1.0h - v.frontColor.a) * out.a;
    }

    return out;
}
