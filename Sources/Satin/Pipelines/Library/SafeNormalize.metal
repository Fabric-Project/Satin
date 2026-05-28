// Normalizing zero-length or non-finite vectors can yield NaNs in Metal.
// Use this at geometry and G-buffer boundaries to fall back to a stable direction.
inline float3 safeNormalize(float3 v, float3 fallback)
{
    const float len2 = dot(v, v);
    return (isfinite(len2) && len2 > 1.0e-12) ? (v * rsqrt(len2)) : fallback;
}

inline float3 orthogonalVector(float3 n)
{
    const float3 axis = (abs(n.z) < 0.999f) ? float3(0.0f, 0.0f, 1.0f) : float3(0.0f, 1.0f, 0.0f);
    return safeNormalize(cross(axis, n), float3(1.0f, 0.0f, 0.0f));
}
