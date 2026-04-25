#include "Library/Gamma.metal"
#include "Library/Tonemap.metal"

typedef struct {
    float4 color;               // color
    float gammaCorrection;      // slider,0.0,1.0,1.0
    float environmentIntensity; // slider,0,1,1
    float blur;                 // slider,0,1,0
    float3x3 texcoordTransform;
} SkyboxUniforms;

typedef struct {
    float4 position [[position]];
    float3 texcoord;
} SkyboxVertexData;

vertex SkyboxVertexData skyboxVertex(
    Vertex v [[stage_in]],
    ushort amp_id [[amplification_id]],
    // inject instancing args
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]]) {
#if INSTANCING
    const float4x4 modelViewProjectionMatrix =
        vertexUniforms[amp_id].viewProjectionMatrix * instanceUniforms[instanceID].modelMatrix;
#else
    const float4x4 modelViewProjectionMatrix = vertexUniforms[amp_id].modelViewProjectionMatrix;
#endif

    const float4 position = float4(v.position, 1.0);
    SkyboxVertexData out;
    out.position = modelViewProjectionMatrix * position;
    out.texcoord = position.xyz;
    return out;
}

fragment float4 skyboxFragment(
    SkyboxVertexData in [[stage_in]],
    constant SkyboxUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texturecube<float> cubeTex [[texture(FragmentTextureCustom0)]],
    sampler cubeTexSampler [[sampler(FragmentSamplerCustom0)]]) {

    const float levels = float(cubeTex.get_num_mip_levels() - 1);
    const float mipLevel = uniforms.blur * levels;

    float4 color =
        cubeTex.sample(cubeTexSampler, uniforms.texcoordTransform * in.texcoord, level(mipLevel));
    color.rgb *= uniforms.environmentIntensity;

    color.rgb = tonemap(color.rgb);

#ifndef TONEMAPPING_UNREAL
    color.rgb = mix(color.rgb, gamma(color.rgb), uniforms.gammaCorrection);
#endif

    return uniforms.color * color;
}
