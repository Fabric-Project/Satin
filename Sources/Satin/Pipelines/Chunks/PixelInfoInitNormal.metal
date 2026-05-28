#include "../Library/SafeNormalize.metal"

#if defined(NORMAL_MAP) && defined(HAS_TEXCOORD)
const float2 normalTexcoord = applyTextureTransform(in.texcoord, uniforms.normalTexcoordTransform);
float3 mapNormal = normalMap.sample(normalSampler, normalTexcoord).rgb * 2.0 - 1.0;

// Keep malformed source normals from destabilizing TBN construction.
float3 normal = safeNormalize(in.normal, float3(0.0f, 0.0f, 1.0f));

#if defined(HAS_TANGENT) && defined(HAS_BITANGENT)
const float3 tangent = safeNormalize(in.tangent, orthogonalVector(normal));
const float3 bitangent = safeNormalize(in.bitangent, cross(normal, tangent));
const float3x3 TBN(tangent, bitangent, normal);
// Clamp invalid tangent-space results back to the geometric normal.
pixel.normal = safeNormalize(TBN * mapNormal, normal);
pixel.tangent = tangent;
pixel.bitangent = bitangent;
#else
const float3 Q1 = dfdx(in.worldPosition);
const float3 Q2 = dfdy(in.worldPosition);
const float2 st1 = dfdx(in.texcoord);
const float2 st2 = dfdy(in.texcoord);

float3 tangent = safeNormalize(Q1 * st2.y - Q2 * st1.y, orthogonalVector(normal));
float3 bitangent = safeNormalize(-cross(normal, tangent), cross(normal, orthogonalVector(normal)));
const float3x3 TBN = float3x3(tangent, bitangent, normal);

// Degenerate UV derivatives should not write NaNs into the deferred normal target.
pixel.normal = safeNormalize(TBN * mapNormal, normal);
pixel.tangent = tangent;
pixel.bitangent = bitangent;
#endif

#else

const float3 Q1 = dfdx(in.worldPosition);
const float3 Q2 = dfdy(in.worldPosition);
const float2 st1 = dfdx(in.texcoord);
const float2 st2 = dfdy(in.texcoord);

// Preserve a finite basis even when triangle or UV derivatives collapse.
float3 normal = safeNormalize(in.normal, float3(0.0f, 0.0f, 1.0f));
float3 tangent = safeNormalize(Q1 * st2.y - Q2 * st1.y, orthogonalVector(normal));
float3 bitangent = safeNormalize(-cross(normal, tangent), cross(normal, orthogonalVector(normal)));

pixel.normal = normal;
pixel.tangent = tangent;
pixel.bitangent = bitangent;
#endif
