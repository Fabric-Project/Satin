#if defined(LIGHTING) && defined(MAX_LIGHTS)
{
    float3 N = pixel.normal;
    float3 V = pixel.view;
    float NdotV = dot(N, V);

    for (int i = 0; i < MAX_LIGHTS; i++) {
        float3 L;
        float lightDistance;
        float3 lightRadiance = getLightInfo(lights[i], pixel.position, L, lightDistance);

#if defined(PROJECTOR_COUNT)
        lightRadiance *= calculateProjectorContribution(
            lights[i],
            pixel.position,
            projectorMatrices,
            projectorTransforms,
            projectorTextures
        );
#endif

#if defined(HAS_SHADOWS) && defined(DIRECT_SHADOW_COUNT) && defined(DIRECT_SHADOW_TEXTURE_COUNT)
        lightRadiance *= calculateDirectShadow(
            lights[i],
            directShadows,
            directShadowMatrices,
            directShadowTextures,
            pixel.position,
            N
        );
#endif

        float NdotL = dot(N, L);
        pixel.radiance += evalBRDF(pixel, L, NdotL, NdotV) * lightRadiance * saturate(NdotL) *
                          pixel.material.occlusion;
    }
}
#endif
