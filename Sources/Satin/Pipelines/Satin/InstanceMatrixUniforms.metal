typedef struct {
    matrix_float4x4 modelMatrix;
    matrix_float3x3 normalMatrix;
    // Last frame's modelMatrix, for velocity. Last, so earlier fields keep their offsets.
    matrix_float4x4 previousModelMatrix;
} InstanceMatrixUniforms;
