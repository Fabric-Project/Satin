typedef enum LightType {
    LightTypeDirectional = 0,
    LightTypePoint = 1,
    LightTypeSpot = 2
} LightType;

typedef struct {
    float4 color;     // (rgb, intensity)
    float4 position;  // (xyz, type)
    float4 direction; // (xyz, inverse radius)
    float4 spotInfo;  // (spotScale, spotOffset, cosInner, cosOuter)
    float4 shadowInfo; // (shadowIndex, projectorIndex, projectorMode, unused)
} LightData;
