typedef struct {
    float4 parameters; // (strength, bias, normalBias, radius)
    uint4 indices; // (textureIndex, matrixIndex, viewCount, unused)
} ShadowData;
