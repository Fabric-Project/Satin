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

static inline float4x4 satinSkinMatrix(Vertex in, constant SkinJoint *joints) {
    const uint4 indices = uint4(in.jointIndices);
    const float4 weights = float4(in.jointWeights);
    return weights.x * joints[indices.x].current +
           weights.y * joints[indices.y].current +
           weights.z * joints[indices.z].current +
           weights.w * joints[indices.w].current;
}

// Only materials that write velocity call this.
__attribute__((unused)) static inline float4x4 satinPreviousSkinMatrix(Vertex in, constant SkinJoint *joints) {
    const uint4 indices = uint4(in.jointIndices);
    const float4 weights = float4(in.jointWeights);
    return weights.x * joints[indices.x].previous +
           weights.y * joints[indices.y].previous +
           weights.z * joints[indices.z].previous +
           weights.w * joints[indices.w].previous;
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
#define SATIN_SKIN_POSITION(v) (satinSkinMatrix(v, skinJoints) * float4(v.position, 1.0))
#define SATIN_PREVIOUS_SKIN_POSITION(v) (satinPreviousSkinMatrix(v, skinJoints) * float4(v.position, 1.0))
#define SATIN_SKIN_DIRECTION(v, direction) (satinSkinNormalMatrix(satinSkinMatrix(v, skinJoints)) * (direction))
#define SATIN_PREVIOUS_SKIN_TRANSFORM(v, position) (satinPreviousSkinMatrix(v, skinJoints) * (position))
#else
#define SATIN_SKIN_POSITION(v) float4(v.position, 1.0)
#define SATIN_PREVIOUS_SKIN_POSITION(v) float4(v.position, 1.0)
#define SATIN_SKIN_DIRECTION(v, direction) (direction)
#define SATIN_PREVIOUS_SKIN_TRANSFORM(v, position) (position)
#endif
#define SATIN_SKIN_NORMAL(v) SATIN_SKIN_DIRECTION(v, v.normal)
