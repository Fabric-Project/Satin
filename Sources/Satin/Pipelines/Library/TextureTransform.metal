float2 applyTextureTransform(float2 uv, float4x4 transform) {
    return (transform * float4(uv, 0.0, 1.0)).xy;
}

float3 applyDirectionTransform(float3 direction, float4x4 transform) {
    return normalize((transform * float4(direction, 0.0)).xyz);
}
