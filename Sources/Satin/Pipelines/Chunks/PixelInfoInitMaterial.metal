#if defined(BASE_COLOR_MAP) && defined(HAS_TEXCOORD)
const float2 baseColorTexcoord =
    applyTextureTransform(in.texcoord, uniforms.baseColorTexcoordTransform);
float4 baseColor = baseColorMap.sample(baseColorSampler, baseColorTexcoord);

const float baseColorAlpha = saturate(baseColor.a);
const uint2 screenPos = uint2(in.position.xy);
const uint bayerIndex = ((screenPos.y & 3u) << 2u) | (screenPos.x & 3u);
const float bayerThresholds[16] = {
    0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
    12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
    3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
    15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0
};

// Ordered dithering softens alpha-cutout edges without requiring MSAA/A2C.
if (baseColorAlpha <= 0.0 || baseColorAlpha < bayerThresholds[bayerIndex])
{
    discard_fragment();
}

pixel.material.baseColor = baseColor.rgb;
pixel.material.baseColor *= uniforms.baseColor.rgb;
#else
pixel.material.baseColor = uniforms.baseColor.rgb;
#endif

#if defined(HAS_COLOR)
pixel.material.baseColor *= in.color.rgb;
#endif

#if defined(EMISSIVE_MAP) && defined(HAS_TEXCOORD)
const float2 emissiveTexcoord = applyTextureTransform(in.texcoord, uniforms.emissiveTexcoordTransform);
pixel.material.emissiveColor = emissiveMap.sample(emissiveSampler, emissiveTexcoord).rgb;
pixel.material.emissiveColor *= uniforms.emissiveColor.rgb * uniforms.emissiveColor.a;
#else
pixel.material.emissiveColor = uniforms.emissiveColor.rgb * uniforms.emissiveColor.a;
#endif

#if defined(SPECULAR_MAP) && defined(HAS_TEXCOORD)
const float2 specularTexcoord = applyTextureTransform(in.texcoord, uniforms.specularTexcoordTransform);
pixel.material.specular = specularMap.sample(specularSampler, specularTexcoord).r;
pixel.material.specular *= uniforms.specular;
#else
pixel.material.specular = uniforms.specular;
#endif

#if defined(METALLIC_MAP) && defined(HAS_TEXCOORD)
const float2 metallicTexcoord = applyTextureTransform(in.texcoord, uniforms.metallicTexcoordTransform);
pixel.material.metallic = metallicMap.sample(metallicSampler, metallicTexcoord).r;
pixel.material.metallic *= uniforms.metallic;
#else
pixel.material.metallic = uniforms.metallic;
#endif

#if defined(ROUGHNESS_MAP) && defined(HAS_TEXCOORD)
const float2 roughnessTexcoord =
    applyTextureTransform(in.texcoord, uniforms.roughnessTexcoordTransform);
pixel.material.roughness = roughnessMap.sample(roughnessSampler, roughnessTexcoord).r;
pixel.material.roughness *= uniforms.roughness;
#else
pixel.material.roughness = uniforms.roughness;
#endif

pixel.material.environmentIntensity = uniforms.environmentIntensity;
pixel.material.gammaCorrection = uniforms.gammaCorrection;

#if defined(HAS_SUBSURFACE)
#if defined(SUBSURFACE_MAP) && defined(HAS_TEXCOORD)
const float2 subsurfaceTexcoord =
    applyTextureTransform(in.texcoord, uniforms.subsurfaceTexcoordTransform);
pixel.material.subsurface = subsurfaceMap.sample(subsurfaceSampler, subsurfaceTexcoord).r;
pixel.material.subsurface *= uniforms.subsurface;
#else
pixel.material.subsurface = uniforms.subsurface;
#endif
#endif

#if defined(HAS_CLEARCOAT)
#if defined(CLEARCOAT_MAP) && defined(HAS_TEXCOORD)
const float2 clearcoatTexcoord =
    applyTextureTransform(in.texcoord, uniforms.clearcoatTexcoordTransform);
pixel.material.clearcoat = clearcoatMap.sample(clearcoatSampler, clearcoatTexcoord).r;
pixel.material.clearcoat *= uniforms.clearcoat;
#else
pixel.material.clearcoat = uniforms.clearcoat;
#endif

#if defined(CLEARCOAT_ROUGHNESS_MAP) && defined(HAS_TEXCOORD)
const float2 clearcoatRoughnessTexcoord =
    applyTextureTransform(in.texcoord, uniforms.clearcoatRoughnessTexcoordTransform);
pixel.material.clearcoatRoughness =
    clearcoatRoughnessMap.sample(clearcoatRoughnessSampler, clearcoatRoughnessTexcoord).r;
pixel.material.clearcoatRoughness *= uniforms.clearcoatRoughness;
#elif defined(CLEARCOAT_GLOSS_MAP) && defined(HAS_TEXCOORD)
const float2 clearcoatGlossTexcoord =
    applyTextureTransform(in.texcoord, uniforms.clearcoatRoughnessTexcoordTransform);
pixel.material.clearcoatRoughness =
    1.0 - clearcoatGlossMap.sample(clearcoatRoughnessSampler, clearcoatGlossTexcoord).r;
pixel.material.clearcoatRoughness *= uniforms.clearcoatRoughness;
#else
pixel.material.clearcoatRoughness = uniforms.clearcoatRoughness;
#endif
#endif

#if defined(HAS_SPECULAR_TINT)
#if defined(SPECULAR_TINT_MAP) && defined(HAS_TEXCOORD)
const float2 specularTintTexcoord =
    applyTextureTransform(in.texcoord, uniforms.specularTintTexcoordTransform);
pixel.material.specularTint = specularTintMap.sample(specularTintSampler, specularTintTexcoord).r;
pixel.material.specularTint *= uniforms.specularTint;
#else
pixel.material.specularTint = uniforms.specularTint;
#endif
#endif

#if defined(HAS_SHEEN)
#if defined(SHEEN_MAP) && defined(HAS_TEXCOORD)
const float2 sheenTexcoord = applyTextureTransform(in.texcoord, uniforms.sheenTexcoordTransform);
pixel.material.sheen = sheenMap.sample(sheenSampler, sheenTexcoord).r;
pixel.material.sheen *= uniforms.sheen;
#else
pixel.material.sheen = uniforms.sheen;
#endif

#if defined(SHEEN_TINT_MAP) && defined(HAS_TEXCOORD)
const float2 sheenTintTexcoord =
    applyTextureTransform(in.texcoord, uniforms.sheenTintTexcoordTransform);
pixel.material.sheenTint = sheenTintMap.sample(sheenTintSampler, sheenTintTexcoord).r;
pixel.material.sheenTint *= uniforms.sheenTint;
#else
pixel.material.sheenTint = uniforms.sheenTint;
#endif
#endif

#if defined(AMBIENT_OCCLUSION_MAP) && defined(HAS_TEXCOORD)
const float2 occlusionTexcoord =
    applyTextureTransform(in.texcoord, uniforms.occlusionTexcoordTransform);
pixel.material.occlusion = occlusionMap.sample(occlusionSampler, occlusionTexcoord).r;
pixel.material.occlusion *= uniforms.occlusion;
#else
pixel.material.occlusion = uniforms.occlusion;
#endif

#if defined(HAS_ANISOTROPIC)
#if defined(ANISOTROPIC_MAP) && defined(HAS_TEXCOORD)
const float2 anisotropicTexcoord =
    applyTextureTransform(in.texcoord, uniforms.anisotropicTexcoordTransform);
pixel.material.anisotropic = anisotropicMap.sample(anisotropicSampler, anisotropicTexcoord).r;
pixel.material.anisotropic *= uniforms.anisotropic;
#else
pixel.material.anisotropic = uniforms.anisotropic;
#endif
#if defined(ANISOTROPIC_ANGLE_MAP) && defined(HAS_TEXCOORD)
const float2 anisotropicAngleTexcoord =
    applyTextureTransform(in.texcoord, uniforms.anisotropicAngleTexcoordTransform);
pixel.material.anisotropicAngle =
    anisotropicAngleMap.sample(anisotropicAngleSampler, anisotropicAngleTexcoord).r;
pixel.material.anisotropicAngle *= uniforms.anisotropicAngle;
#else
pixel.material.anisotropicAngle = uniforms.anisotropicAngle;
#endif
#endif

#if defined(ALPHA_MAP) && defined(HAS_TEXCOORD)
const float2 alphaTexcoord = applyTextureTransform(in.texcoord, uniforms.alphaTexcoordTransform);
pixel.material.alpha = alphaMap.sample(alphaSampler, alphaTexcoord).r;
pixel.material.alpha *= uniforms.baseColor.a;
#else
pixel.material.alpha = uniforms.baseColor.a;
#endif

#if defined(HAS_COLOR)
pixel.material.alpha *= in.color.a;
#endif

#if defined(HAS_TRANSMISSION)
pixel.material.thickness = in.thickness;

#if defined(TRANSMISSION_MAP) && defined(HAS_TEXCOORD)
const float2 transmissionTexcoord =
    applyTextureTransform(in.texcoord, uniforms.transmissionTexcoordTransform);
pixel.material.transmission = transmissionMap.sample(transmissionSampler, transmissionTexcoord).r;
pixel.material.transmission *= uniforms.transmission;
#else
pixel.material.transmission = uniforms.transmission;
#endif

#if defined(IOR_MAP) && defined(HAS_TEXCOORD)
const float2 iorTexcoord = applyTextureTransform(in.texcoord, uniforms.iorTexcoordTransform);
pixel.material.ior = iorMap.sample(iorSampler, iorTexcoord).r;
pixel.material.ior *= uniforms.ior;
#else
pixel.material.ior = uniforms.ior;
#endif

#endif

pixel.material.reflectionTexcoordTransform = uniforms.reflectionTexcoordTransform;
pixel.material.irradianceTexcoordTransform = uniforms.irradianceTexcoordTransform;
