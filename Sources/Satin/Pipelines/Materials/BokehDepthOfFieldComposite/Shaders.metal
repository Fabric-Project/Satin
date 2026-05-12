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

static bool bokehDepthOfFieldDepthIsClearOrInvalid(float depth) {
    return depth <= 1.0e-6f || depth >= (1.0f - 1.0e-6f);
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

    float centerFarBlend = 1.0f;
    float centerNearBlend = 0.0f;
//    if (bokehDepthOfFieldDepthIsClearOrInvalid(depth) == false) {
        const float viewDistance = bokehDepthOfFieldViewDistance(uv, depth, uniforms.inverseProjectionMatrix);
        const float signedRadius = bokehDepthOfFieldSignedRadius(
            viewDistance,
            uniforms.focusDistance,
            uniforms.focusRange,
            uniforms.maxBlurRadius
        );
        centerNearBlend = saturate(max(-signedRadius, 0.0f));
        centerFarBlend = saturate(max(signedRadius, 0.0f));
//    }

    const float4 farSample = farBlurTex.sample(linearSampler, uv);
    const float4 nearSample = nearBlurTex.sample(linearSampler, uv);

    const float farWeight = saturate(farSample.a);
    const float nearWeight = saturate(nearSample.a);

    const float3 farColor = farWeight > 1.0e-4f ? max(farSample.rgb / farWeight, 0.0f) : sharpSample.rgb;
    const float3 nearColor = nearWeight > 1.0e-4f ? max(nearSample.rgb / nearWeight, 0.0f) : sharpSample.rgb;

    const float farBlend = centerFarBlend * farWeight;
    const float nearBlend = centerNearBlend * nearWeight; //max(centerNearBlend, nearWeight);

    float3 result = mix(sharpSample.rgb, farColor, farBlend);
    result = mix(result, nearColor, nearBlend);

    const float resultAlpha = saturate(max(sharpSample.a, max(farBlend, nearBlend)));

    return half4(half3(result), half(resultAlpha));
}
