// Linear blend skinning, after GLTFKit (Warren Moore, GLTFViewer/Resources/Shaders/pbr.metal).
//
// A skinned vertex is moved by up to four joints: its position is the weighted sum of each
// joint's matrix applied to it. The joint matrices (the palette) come from `JointPalette`,
// one entry per joint holding this frame's matrix and last frame's, so velocity can be
// computed. Skinning happens in object space, before the model or instance transform.
//
// Nothing here is compiled unless SKINNING is defined and the geometry carries joint indices
// and weights, so shaders for unskinned geometry are unaffected.

typedef struct {
    float4x4 current;
    float4x4 previous;
} SkinJoint;

#if defined(SKINNING) && defined(HAS_JOINTINDICES) && defined(HAS_JOINTWEIGHTS)
#define SATIN_SKINNED 1

// This frame's skin matrix, or last frame's when `previous`; inlined with a constant, so the
// choice costs nothing.
static inline float4x4 satinSkinMatrix(Vertex in, constant SkinJoint *joints, bool previous) {
    const uint4 indices = uint4(in.jointIndices);
    const float4 weights = float4(in.jointWeights);
    return weights.x * (previous ? joints[indices.x].previous : joints[indices.x].current) +
           weights.y * (previous ? joints[indices.y].previous : joints[indices.y].current) +
           weights.z * (previous ? joints[indices.z].previous : joints[indices.z].current) +
           weights.w * (previous ? joints[indices.w].previous : joints[indices.w].current);
}

// The upper 3x3 of a skin matrix, for normals and tangents: exact for rigid and uniformly
// scaled joints, approximate under non-uniform joint scale (as in GLTFKit).
static inline float3x3 satinSkinNormalMatrix(float4x4 skin) {
    return float3x3(skin[0].xyz, skin[1].xyz, skin[2].xyz);
}
#endif

// What vertex functions use in place of the raw attributes. Without skinning they expand to
// exactly the expressions they replace, so unskinned shaders compile to the same code.
// `v` is the stage_in vertex; skinned builds read the injected `skinJoints` argument.
#if SATIN_SKINNED
#define SATIN_SKIN_POSITION(v) (satinSkinMatrix(v, skinJoints, false) * float4(v.position, 1.0))
#define SATIN_PREVIOUS_SKIN_POSITION(v) (satinSkinMatrix(v, skinJoints, true) * float4(v.position, 1.0))
#define SATIN_SKIN_DIRECTION(v, direction) (satinSkinNormalMatrix(satinSkinMatrix(v, skinJoints, false)) * (direction))
#define SATIN_PREVIOUS_SKIN_TRANSFORM(v, position) (satinSkinMatrix(v, skinJoints, true) * (position))
#else
#define SATIN_SKIN_POSITION(v) float4(v.position, 1.0)
#define SATIN_PREVIOUS_SKIN_POSITION(v) float4(v.position, 1.0)
#define SATIN_SKIN_DIRECTION(v, direction) (direction)
#define SATIN_PREVIOUS_SKIN_TRANSFORM(v, position) (position)
#endif
#define SATIN_SKIN_NORMAL(v) SATIN_SKIN_DIRECTION(v, v.normal)

// Where `v` was last frame, in object space then clip space, for velocity. Custom10 is
// VertexAttributeIndex.PreviousPosition: last frame's position for geometry deformed on the CPU.
// Each instance uses its own last-frame matrix. The clip-space form reads the vertex function's
// `vertexUniforms` and `amp_id`, and when instancing `instanceUniforms` and `instanceID`.
#if defined(HAS_CUSTOM10)
#define SATIN_PREVIOUS_POSITION(v) SATIN_PREVIOUS_SKIN_TRANSFORM(v, float4(v.custom10.xyz, 1.0))
#else
#define SATIN_PREVIOUS_POSITION(v) SATIN_PREVIOUS_SKIN_POSITION(v)
#endif
#if defined(INSTANCING)
#define SATIN_PREVIOUS_CLIP_POSITION(v) (vertexUniforms[amp_id].previousViewProjectionMatrix * instanceUniforms[instanceID].previousModelMatrix * SATIN_PREVIOUS_POSITION(v))
#else
#define SATIN_PREVIOUS_CLIP_POSITION(v) (vertexUniforms[amp_id].previousModelViewProjectionMatrix * SATIN_PREVIOUS_POSITION(v))
#endif
