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
    constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

    const float2 uv = in.texcoord;
    const float4 sharpSample = colorTex.sample(linearSampler, uv);
    const float depth = depthTex.sample(nearestSampler, uv);

    const float viewDistance = bokehDepthOfFieldViewDistance(uv, depth, uniforms.inverseProjectionMatrix);
    const float signedRadius = bokehDepthOfFieldSignedRadius(
        viewDistance,
        uniforms.focusDistance,
        uniforms.focusRange,
        uniforms.maxBlurRadius
    );
    const float inverseMaxBlurRadius = 1.0f / max(uniforms.maxBlurRadius, 1.0e-4f);
    const float nearBlend = saturate(max(-signedRadius, 0.0f) * inverseMaxBlurRadius);
    const float farBlend = saturate(max(signedRadius, 0.0f) * inverseMaxBlurRadius);
    const float sharpBlend = saturate(1.0f - nearBlend - farBlend);

    const float4 farSample = farBlurTex.sample(linearSampler, uv);
    const float4 nearSample = nearBlurTex.sample(linearSampler, uv);
    const float3 farColor = farSample.rgb;
    const float3 nearColor = nearSample.rgb;

    const float3 result =
        sharpSample.rgb * sharpBlend +
        nearColor * nearBlend +
        farColor * farBlend;

    const float resultAlpha = 1.0;
//        sharpSample.a * sharpBlend +
//        nearSample.a * nearBlend +
//        farSample.a * farBlend;

    return half4(half3(result), half(resultAlpha));
}
