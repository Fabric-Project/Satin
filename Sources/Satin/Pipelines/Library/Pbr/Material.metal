struct Material {
    float3 baseColor;
    float3 emissiveColor;
#if defined(HAS_SUBSURFACE)
    float subsurface;
#endif
    float occlusion;
    float metallic;
    float roughness;
    float specular;
    float environmentIntensity;
    float gammaCorrection;
#if defined(HAS_SPECULAR_TINT)
    float specularTint;
#endif
#if defined(HAS_ANISOTROPIC)
    float anisotropic;
    float anisotropicAngle;
#endif
    float alpha;
#if defined(HAS_CLEARCOAT)
    float clearcoat;
    float clearcoatRoughness;
#endif
#if defined(HAS_SHEEN)
    float sheen;
    float sheenTint;
#endif
#if defined(HAS_TRANSMISSION)
    float transmission;
    float3 thickness; // already multiplied by the modelView's scale matrix
    float ior;
#endif
    float3x3 reflectionTexcoordTransform;
    float3x3 irradianceTexcoordTransform;
};
