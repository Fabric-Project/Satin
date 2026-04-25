#include "Satin/PbrConstants.metal"

#include "Library/Pbr/Pbr.metal"

typedef struct {
#include "Chunks/PhysicalUniforms.metal"
} PhysicalUniforms;

typedef struct {
    float4 position [[position]];
    // inject shadow coords
    float3 normal;
    float2 texcoord;

#if defined(HAS_COLOR)
    float4 color;
#endif

#if defined(HAS_TANGENT)
    float3 tangent;
#endif

#if defined(HAS_BITANGENT)
    float3 bitangent;
#endif

    float3 worldPosition;
    float3 cameraPosition;
#if defined(HAS_TRANSMISSION)
    float3 thickness;
#endif
} CustomVertexData;

vertex CustomVertexData physicalVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    // inject shadow vertex args
    constant PhysicalUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]],
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
#if defined(INSTANCING)
    const float3x3 normalMatrix = instanceUniforms[instanceID].normalMatrix;
    const float4x4 modelMatrix = instanceUniforms[instanceID].modelMatrix;
#else
    const float3x3 normalMatrix = vertexUniforms[amp_id].normalMatrix;
    const float4x4 modelMatrix = vertexUniforms[amp_id].modelMatrix;
#endif

    const float4 position = float4(in.position, 1.0);
    const float4 worldPosition = modelMatrix * position;
    CustomVertexData out;
    out.position = vertexUniforms[amp_id].viewProjectionMatrix * worldPosition;
#if defined(HAS_TEXCOORD)
    out.texcoord = in.texcoord;
#endif
    out.normal = normalMatrix * in.normal;

#if defined(HAS_COLOR)
    out.color = float4(in.color.rgb, 1.0);
#endif

#if defined(HAS_TANGENT)
    out.tangent = normalMatrix * in.tangent;
#endif

#if defined(HAS_BITANGENT)
    out.bitangent = in.bitangent;
#endif

    out.worldPosition = worldPosition.xyz;
    out.cameraPosition = vertexUniforms[amp_id].worldCameraPosition.xyz;
#if defined(HAS_TRANSMISSION)
    float3 modelScale;
    modelScale.x = length(modelMatrix[0].xyz);
    modelScale.y = length(modelMatrix[1].xyz);
    modelScale.z = length(modelMatrix[2].xyz);
    out.thickness = uniforms.thickness * modelScale;
#endif

    // inject shadow vertex calc

    return out;
}

fragment float4 physicalFragment(
    CustomVertexData in [[stage_in]],
// inject lighting args
// inject shadow fragment args
#include "Chunks/PbrTextures.metal"
    constant PhysicalUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
    float4 outColor;

#include "Chunks/PixelInfoInit.metal"
#include "Chunks/PbrInit.metal"
#include "Chunks/PbrDirectLighting.metal"
#include "Chunks/PbrInDirectLighting.metal"
#include "Chunks/PbrTonemap.metal"
    // inject shadow fragment calc
    return outColor;
}
