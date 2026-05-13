typedef struct {
    float4x4 inverseProjectionMatrix;
    float focusDistance;
    float focusRange;
    float maxBlurRadius;
    float compositePadding;
} BokehDepthOfFieldCompositeUniforms;

static float bokehDepthOfFieldViewDistance(
    float2 uv,
    float depth,
    float4x4 inverseProjectionMatrix
) {
    const float4 clipPosition = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    const float4 viewPosition = inverseProjectionMatrix * clipPosition;
    return max(-viewPosition.z / max(viewPosition.w, 1.0e-6f), 0.0f);
}

static float bokehDepthOfFieldSignedRadius(
    float viewDistance,
    float focusDistance,
    float focusRange,
    float maxBlurRadius
) {
    const float halfRange = max(focusRange * 0.5f, 1.0e-4f);
    const float falloffRange = max(focusRange, 1.0e-4f);
    const float delta = viewDistance - focusDistance;

    float signedCoC = 0.0f;
    if (delta < -halfRange) {
        signedCoC = (delta + halfRange) / halfRange;
    } else if (delta > halfRange) {
        signedCoC = (delta - halfRange) / halfRange;
    }

    return clamp(signedCoC, -1.0f, 1.0f) * maxBlurRadius;
}

fragment half4 bokehDepthOfFieldCompositeFragment(
    VertexData in [[stage_in]],
    constant BokehDepthOfFieldCompositeUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
    texture2d<float, access::sample> colorTex [[texture(FragmentTextureCustom0)]],
    depth2d<float, access::sample> depthTex [[texture(FragmentTextureCustom1)]],
    texture2d<float, access::sample> farBlurTex [[texture(FragmentTextureCustom2)]],
    texture2d<float, access::sample> nearBlurTex [[texture(FragmentTextureCustom3)]]
) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float4 sharpSample = colorTex.sample(linearSampler, uv);
    const float4 farSample = farBlurTex.sample(linearSampler, uv);
    const float4 nearSample = nearBlurTex.sample(linearSampler, uv);

    // Composite explicit near/far planes rather than reclassifying the destination pixel from full-res
    // depth. This more closely matches the Garcia circular DOF pipeline where the split planes are the
    // source of truth after downsample/split.
    // Garcia explicitly recommends transitioning to the blurred near plane quickly to avoid
    // silhouette ghosting. Bias the near layer aggressively once support is present.
    const float nearSupport = saturate(nearSample.a);
    const float farSupport = saturate(farSample.a);
    const float nearOpacity = smoothstep(0.05f, 0.35f, nearSupport);
    const float farOpacity = smoothstep(0.05f, 0.35f, farSupport);

    const float nearVisibility = nearOpacity;
    const float farVisibility = farOpacity * (1.0f - nearVisibility);
    const float sharpVisibility = saturate(1.0f - nearVisibility - farVisibility);

    const float visibilitySum = max(nearVisibility + farVisibility + sharpVisibility, 1.0e-4f);
    const float3 result =
        sharpSample.rgb * (sharpVisibility / visibilitySum) +
        farSample.rgb * (farVisibility / visibilitySum) +
        nearSample.rgb * (nearVisibility / visibilitySum);

    const float resultAlpha = 1.0;//saturate(sharpSample.a + farVisibility + nearVisibility);

    return half4(half3(result), half(resultAlpha));
}
