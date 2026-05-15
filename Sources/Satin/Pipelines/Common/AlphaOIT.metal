#include <metal_stdlib>
using namespace metal;

static constexpr constant short kAlphaOitLayerCount = 4;

struct AlphaOitFragmentValues
{
    half4 colors [[raster_order_group(0)]] [kAlphaOitLayerCount];
    half depths [[raster_order_group(0)]] [kAlphaOitLayerCount];
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
    threadgroup_imageblock AlphaOitFragmentValues *fragmentValues = blockData.data(localThreadID);
    for (short i = 0; i < kAlphaOitLayerCount; ++i) {
        fragmentValues->colors[i] = half4(0.0h);
        fragmentValues->depths[i] = half(INFINITY);
    }
}

fragment half4 alphaOitBlendFragment(
    AlphaOitFragmentValues fragmentValues [[imageblock_data]],
    half4 backgroundColor [[color(0), raster_order_group(0)]]
) {
    half4 out = backgroundColor;

    for (short i = kAlphaOitLayerCount - 1; i >= 0; --i) {
        const half4 layerColor = fragmentValues.colors[i];
        out.rgb = layerColor.rgb + (1.0h - layerColor.a) * out.rgb;
        out.a = layerColor.a + (1.0h - layerColor.a) * out.a;
    }

    return out;
}
