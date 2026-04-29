#include "../../Library/Dither.metal"
#include "../../Includes/FragmentOutput.metal"

typedef struct {
    float4 position [[position]];
    float3 viewPosition;
    float3 normal;
    float3 worldNormal;

#ifdef OUTPUT_VELOCITY
    float4 currentClipPos;
    float4 previousClipPos;
#endif
} BasicDiffuseVertexData;

typedef struct {
    float4 color;       // color
    float hardness;     // slider
    float diffusePower; // slider,0,2,0.5
} BasicDiffuseUniforms;

vertex BasicDiffuseVertexData basicDiffuseVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
    const float4 position = float4(in.position, 1.0);
#if INSTANCING
    const float3x3 normalMatrix = instanceUniforms[instanceID].normalMatrix;
    const float4x4 modelMatrix = instanceUniforms[instanceID].modelMatrix;

    const float4 viewPosition = vertexUniforms[amp_id].viewMatrix * modelMatrix * position;
    const float3 normal = normalMatrix * in.normal;
#else
    const float4 viewPosition = vertexUniforms[amp_id].modelViewMatrix * position;
    const float3 normal = vertexUniforms[amp_id].normalMatrix * in.normal;
#endif

    const float4 screenSpaceNormal = vertexUniforms[amp_id].viewMatrix * float4(normal, 0.0);

    BasicDiffuseVertexData out;
    out.viewPosition = viewPosition.xyz;
    out.position = vertexUniforms[amp_id].projectionMatrix * viewPosition;
    out.normal = screenSpaceNormal.xyz;
    out.worldNormal = normal;

#ifdef OUTPUT_VELOCITY
    out.currentClipPos = out.position;
#if INSTANCING
    out.previousClipPos = vertexUniforms[amp_id].previousViewProjectionMatrix * modelMatrix * position;
#else
    out.previousClipPos = vertexUniforms[amp_id].previousModelViewProjectionMatrix * position;
#endif
#endif

    return out;
}

fragment FragmentOutput basicDiffuseFragment(
    BasicDiffuseVertexData in [[stage_in]],
    constant BasicDiffuseUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
    float4 outColor;

#if defined(DEFERRED_GEOMETRY)
    outColor = float4(0.0, 0.0, 0.0, uniforms.color.a);
#else
    outColor = uniforms.color;

    const float3 pos = in.viewPosition;
    const float3 dx = normalize(dfdx(pos));
    const float3 dy = normalize(dfdy(pos));
    const float3 normal = normalize(cross(dx, dy));
    const float soft = dot(normalize(in.normal), float3(0.0, 0.0, 1.0));
    const float hard = saturate(dot(normal, float3(0.0, 0.0, -1.0)));

    outColor.rgb *= pow(mix(soft, hard, uniforms.hardness), uniforms.diffusePower);
    outColor.rgb = dither8x8(in.position.xy, outColor.rgb);
#endif

    SurfaceOutput surface;
    surface.albedo    = half3(uniforms.color.rgb);
    surface.normal    = half3(normalize(in.worldNormal));
    surface.roughness = 1.0h;
    surface.metalness = 0.0h;
    surface.ao        = 1.0h;
    surface.emissive  = half3(0.0h);

    return buildFragmentOutput(surface, half4(outColor)
#ifdef OUTPUT_VELOCITY
        , in.currentClipPos, in.previousClipPos
#endif
    );
}
