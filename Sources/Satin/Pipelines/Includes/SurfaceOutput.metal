#include "RendererAttachments.metal"
#include "AlphaOIT.metal"

// What a surface material provides. Materials fill this from evaluateSurface(); the framework
// handles lighting and output routing via buildFragmentOutput() in FragmentOutput.metal.
// Unlit materials do not use this struct — their fragment functions return FragmentOutput directly.
typedef struct {
    half3 albedo;
    half  alpha;
    half3 normal;    // world-space; need not be pre-normalized
    half  roughness;
    half  metalness;
    half  ao;
    half3 emissive;
} SurfaceOutput;

// Fragment output struct. Fields are conditionally compiled based on active OUTPUT_* defines,
// which are injected by Context.getDefines() when the corresponding RendererOutputs flag is set.
#ifdef ALPHA_OIT
typedef AlphaOitFragmentStore FragmentOutput;
#else
typedef struct {
    half4 color [[color(ATTACHMENT_COLOR)]];
#ifdef OUTPUT_ALBEDO
    half4 albedo   [[color(ATTACHMENT_ALBEDO)]];
#endif
#ifdef OUTPUT_NORMALS
    half4 normal   [[color(ATTACHMENT_NORMALS)]];
#endif
#ifdef OUTPUT_PBR
    half4 pbr      [[color(ATTACHMENT_PBR)]];
#endif
#ifdef OUTPUT_VELOCITY
    half2 velocity [[color(ATTACHMENT_VELOCITY)]];
#endif
#ifdef OUTPUT_EMISSIVE
    half4 emissive [[color(ATTACHMENT_EMISSIVE)]];
#endif
} FragmentOutput;
#endif
