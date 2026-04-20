inline int getLightShadowIndex(const LightData light) {
    return int(light.shadowInfo.x);
}

inline int getLightProjectorIndex(const LightData light) {
    return int(light.shadowInfo.y);
}

inline int getLightProjectorMode(const LightData light) {
    return int(light.shadowInfo.z);
}

inline float3 projectorIdentity() {
    return float3(1.0);
}

inline float shadowIdentity() {
    return 1.0;
}

inline float shadowFrustum(float4 shadowCoord) {
    shadowCoord.xyz /= shadowCoord.w;
    const float3 v = abs(shadowCoord.xyz) - 1.0;
    return step(max(max(v.x, v.y), v.z), 0.0);
}

inline int getPointShadowFace(float3 direction) {
    const float3 absoluteDirection = abs(direction);
    if (absoluteDirection.x >= absoluteDirection.y && absoluteDirection.x >= absoluteDirection.z) {
        return direction.x >= 0.0 ? 0 : 1;
    }

    if (absoluteDirection.y >= absoluteDirection.x && absoluteDirection.y >= absoluteDirection.z) {
        return direction.y >= 0.0 ? 2 : 3;
    }

    return direction.z >= 0.0 ? 4 : 5;
}

#if defined(PROJECTOR_COUNT)
inline float3 calculateProjectorContribution(
    const LightData light,
    float3 worldPosition,
    constant float4x4 *projectorMatrices,
    constant float4x4 *projectorTransforms,
    array<texture2d<float>, PROJECTOR_COUNT> projectorTextures
) {
    const int projectorIndex = getLightProjectorIndex(light);
    if (projectorIndex < 0 || projectorIndex >= PROJECTOR_COUNT) {
        return projectorIdentity();
    }

    constexpr sampler projectorSampler(coord::normalized, address::clamp_to_zero, filter::linear);

    float4 projectorCoord = projectorMatrices[projectorIndex] * float4(worldPosition, 1.0);
    if (shadowFrustum(projectorCoord) == 0.0) {
        return projectorIdentity();
    }

    projectorCoord.xyz /= projectorCoord.w;
    float2 uv = 0.5 + float2(projectorCoord.x, -projectorCoord.y) * 0.5;
    const float4 transformedUV = projectorTransforms[projectorIndex] * float4(uv, 0.0, 1.0);
    uv = transformedUV.xy;

    if (any(uv < 0.0) || any(uv > 1.0)) {
        return projectorIdentity();
    }

    const float4 sample = projectorTextures[projectorIndex].sample(projectorSampler, uv);
    const int projectorMode = getLightProjectorMode(light);
    if (projectorMode == 2) {
        return sample.rgb;
    }

    const float mask = max(sample.a, dot(sample.rgb, float3(0.2126, 0.7152, 0.0722)));
    return float3(mask);
}
#endif

#if defined(DIRECT_SHADOW_COUNT) && defined(DIRECT_SHADOW_TEXTURE_COUNT)
inline float calculateDirectShadow(
    const LightData light,
    constant ShadowData *shadowData,
    constant float4x4 *shadowMatrices,
    array<depth2d<float>, DIRECT_SHADOW_TEXTURE_COUNT> shadowTextures,
    float3 worldPosition,
    float3 surfaceNormal
) {
    const int shadowIndex = getLightShadowIndex(light);
    if (shadowIndex < 0 || shadowIndex >= DIRECT_SHADOW_COUNT) {
        return shadowIdentity();
    }

    const ShadowData shadow = shadowData[shadowIndex];
    const int matrixIndex = int(shadow.indices.y);
    const int textureIndex = int(shadow.indices.x);
    const int viewCount = int(shadow.indices.z);
    const float3 biasedPosition = worldPosition + surfaceNormal * shadow.parameters.z;

    constexpr sampler shadowSampler(coord::normalized, address::clamp_to_edge, filter::linear, compare_func::greater_equal);

    if (viewCount > 1) {
        const int faceIndex = getPointShadowFace(biasedPosition - light.position.xyz);
        const int pointMatrixIndex = matrixIndex + faceIndex;
        const int pointTextureIndex = textureIndex + faceIndex;
        if (pointMatrixIndex >= DIRECT_SHADOW_TEXTURE_COUNT || pointTextureIndex >= DIRECT_SHADOW_TEXTURE_COUNT) {
            return shadowIdentity();
        }

        const float4 shadowCoord = shadowMatrices[pointMatrixIndex] * float4(biasedPosition, 1.0);
        return calculateShadow(shadowCoord, shadowTextures[pointTextureIndex], shadow, shadowSampler);
    }

    const float4 shadowCoord = shadowMatrices[matrixIndex] * float4(biasedPosition, 1.0);
    return calculateShadow(shadowCoord, shadowTextures[textureIndex], shadow, shadowSampler);
}
#endif
