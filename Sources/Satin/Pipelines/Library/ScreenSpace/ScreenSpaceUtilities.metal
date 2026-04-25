static float3 satinReconstructViewPosition(
    float2 uv,
    float depth,
    float4x4 inverseProjectionMatrix
) {
    const float4 clipPosition = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    const float4 viewPosition = inverseProjectionMatrix * clipPosition;
    return viewPosition.xyz / max(viewPosition.w, 1.0e-6);
}

static float2 satinProjectViewPositionToUv(
    float3 viewPosition,
    float4x4 projectionMatrix
) {
    const float4 clipPosition = projectionMatrix * float4(viewPosition, 1.0);
    const float2 ndc = clipPosition.xy / max(clipPosition.w, 1.0e-6);
    return float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

static float3 satinDecodeWorldNormal(float3 encodedNormal) {
    return encodedNormal * 2.0 - 1.0;
}

static float3 satinDecodeViewNormal(float3 encodedNormal, float4x4 viewMatrix) {
    const float3 worldNormal = satinDecodeWorldNormal(encodedNormal);
    return normalize((viewMatrix * float4(worldNormal, 0.0)).xyz);
}

static bool satinUvInside(float2 uv) {
    return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}
