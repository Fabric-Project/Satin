#include "MetalIncludes.metal"
#include "VertexConstants.metal"
#include "FragmentConstants.metal"

// inject defines
// inject constants

#include "LightData.metal"
#include "ShadowData.metal"
#include "../Library/Shadow.metal"
#include "../Library/RealtimeShadows.metal"

// inject vertex
#include "VertexData.metal"

#include "VertexUniforms.metal"
#include "InstanceMatrixUniforms.metal"

// inject shadow shader
// inject vertex shader
