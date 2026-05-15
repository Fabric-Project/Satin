#include "Satin/PbrConstants.metal"

#include "../../Library/Dither.metal"
#include "../../Includes/FragmentOutput.metal"

typedef struct {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 worldNormal;
    float3 worldPosition;
    float3 cameraPosition;

#ifdef OUTPUT_VELOCITY
    float4 currentClipPos;
    float4 previousClipPos;
#endif
} BasicDiffuseVertexData;

typedef struct {
    float4 color;       // color
    float ambient;      // slider,0,1,0
    float hardness;     // slider
    float diffusePower; // slider,0,2,0.5
    float pointSize;    // slider,1.0,64.0,1.0
} BasicDiffuseUniforms;

float getBasicDiffuseSquareFalloffAttenuation(float distanceSquare, float lightInvRadius) {
    const float factor = distanceSquare * lightInvRadius * lightInvRadius;
    const float smoothFactor = max(1.0 - factor * factor, 0.0);
    return (smoothFactor * smoothFactor) / max(distanceSquare, 1e-4);
}

float getBasicDiffuseSpotAngleAttenuation(float3 fragmentToLightDirection, float3 lightDirection, float2 spotInfo) {
    const float coneDot = dot(lightDirection, fragmentToLightDirection);
    const float attenuation = saturate(coneDot * spotInfo.x + spotInfo.y);
    return attenuation * attenuation;
}

float getBasicDiffuseFallbackFactor(
    float3 worldPosition,
    float3 worldNormal,
    float3 cameraPosition,
    float hardness,
    float diffusePower
) {
    const float3 viewPosition = cameraPosition - worldPosition;
    const float3 dx = normalize(dfdx(viewPosition));
    const float3 dy = normalize(dfdy(viewPosition));
    const float3 geometricNormal = normalize(cross(dx, dy));
    const float3 viewDirection = normalize(viewPosition);

    const float soft = saturate(dot(normalize(worldNormal), viewDirection));
    const float hard = saturate(dot(geometricNormal, -viewDirection));
    const float fallbackFactor = mix(soft, hard, saturate(hardness));

    return pow(max(fallbackFactor, 1e-4), max(diffusePower, 1e-4));
}

float3 getBasicDiffuseLightInfo(
    const LightData light,
    float3 worldPosition,
    thread float3 &lightDirection,
    thread float &lightDistance
) {
    float3 lightRadiance = light.color.rgb * light.color.a;
    const float3 lightPosition = light.position.xyz;
    const LightType lightType = (LightType)light.position.w;

    lightDirection = light.direction.xyz;
    lightDistance = INFINITY;

    if (lightType > LightTypeDirectional) {
        const float inverseRadius = light.direction.w;
        const float3 worldToLight = lightPosition - worldPosition;
        const float distanceSquare = dot(worldToLight, worldToLight);

        lightRadiance *= getBasicDiffuseSquareFalloffAttenuation(distanceSquare, inverseRadius);
        lightDistance = sqrt(distanceSquare);
        lightDirection = worldToLight / lightDistance;

        if (lightType > LightTypePoint) {
            lightRadiance *= getBasicDiffuseSpotAngleAttenuation(
                lightDirection,
                light.direction.xyz,
                light.spotInfo.xy
            );
        }
    }

    return lightRadiance;
}

vertex BasicDiffuseVertexData basicDiffuseVertex(
    Vertex in [[stage_in]],
    // inject instancing args
    ushort amp_id [[amplification_id]],
    constant VertexUniforms *vertexUniforms [[buffer(VertexBufferVertexUniforms)]],
    constant BasicDiffuseUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]]) {
    const float4 position = float4(in.position, 1.0);
#if INSTANCING
    const float3x3 normalMatrix = instanceUniforms[instanceID].normalMatrix;
    const float4x4 modelMatrix = instanceUniforms[instanceID].modelMatrix;
#else
    const float3x3 normalMatrix = vertexUniforms[amp_id].normalMatrix;
    const float4x4 modelMatrix = vertexUniforms[amp_id].modelMatrix;
#endif
    const float4 worldPosition = modelMatrix * position;
    const float3 worldNormal = normalMatrix * in.normal;

    BasicDiffuseVertexData out;
    out.position = vertexUniforms[amp_id].viewProjectionMatrix * worldPosition;
    out.pointSize = uniforms.pointSize;
    out.worldNormal = worldNormal;
    out.worldPosition = worldPosition.xyz;
    out.cameraPosition = vertexUniforms[amp_id].worldCameraPosition.xyz;

#ifdef OUTPUT_VELOCITY
    out.currentClipPos = out.position;
#if INSTANCING
    out.previousClipPos = vertexUniforms[amp_id].previousViewProjectionMatrix * modelMatrix * position;
#else
    out.previousClipPos = vertexUniforms[amp_id].previousModelViewProjectionMatrix * position;
#endif
#endif

    return out;
}

fragment FragmentOutput basicDiffuseFragment(
    BasicDiffuseVertexData in [[stage_in]],
// inject lighting args
#if defined(PROJECTOR_COUNT)
    constant float4x4 *projectorMatrices [[buffer(FragmentBufferProjectorMatrices)]],
    constant float4x4 *projectorTransforms [[buffer(FragmentBufferProjectorTransforms)]],
    array<texture2d<float>, PROJECTOR_COUNT> projectorTextures [[texture(FragmentTextureProjector0)]],
#endif
#if defined(DIRECT_SHADOW_COUNT) && defined(DIRECT_SHADOW_TEXTURE_COUNT)
    constant ShadowData *directShadows [[buffer(FragmentBufferDirectShadows)]],
    constant float4x4 *directShadowMatrices [[buffer(FragmentBufferDirectShadowMatrices)]],
    array<depth2d<float>, DIRECT_SHADOW_TEXTURE_COUNT> directShadowTextures [[texture(FragmentTextureDirectShadow0)]],
#endif
    constant BasicDiffuseUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]
    SATIN_ALPHA_OIT_FRAGMENT_DATA) {
    float4 outColor = float4(0.0, 0.0, 0.0, uniforms.color.a);

    const float3 N = normalize(in.worldNormal);

#if defined(DEFERRED_GEOMETRY)
#else
    float3 litRgb = uniforms.color.rgb * max(uniforms.ambient, 0.0);

#if defined(LIGHTING) && defined(MAX_LIGHTS)
    const float hardnessExponent = mix(0.75, max(uniforms.diffusePower, 1.0), saturate(uniforms.hardness));
    for (int i = 0; i < MAX_LIGHTS; i++) {
        float3 lightDirection;
        float lightDistance;
        float3 lightRadiance = getBasicDiffuseLightInfo(
            lights[i],
            in.worldPosition,
            lightDirection,
            lightDistance
        );

#if defined(PROJECTOR_COUNT)
        lightRadiance *= calculateProjectorContribution(
            lights[i],
            in.worldPosition,
            projectorMatrices,
            projectorTransforms,
            projectorTextures
        );
#endif

#if defined(HAS_SHADOWS) && defined(DIRECT_SHADOW_COUNT) && defined(DIRECT_SHADOW_TEXTURE_COUNT)
        lightRadiance *= calculateDirectShadow(
            lights[i],
            directShadows,
            directShadowMatrices,
            directShadowTextures,
            in.worldPosition,
            N
        );
#endif

        const float diffuseFactor = pow(saturate(dot(N, lightDirection)), hardnessExponent);
        litRgb += uniforms.color.rgb * lightRadiance * diffuseFactor;
    }
#else
    litRgb = uniforms.color.rgb * max(
        max(uniforms.ambient, 0.0),
        getBasicDiffuseFallbackFactor(
            in.worldPosition,
            N,
            in.cameraPosition,
            uniforms.hardness,
            uniforms.diffusePower
        )
    );
#endif

    outColor.rgb = dither8x8(in.position.xy, litRgb);
#endif

    SurfaceOutput surface;
    surface.albedo    = half3(uniforms.color.rgb);
    surface.alpha     = half(uniforms.color.a);
    surface.normal    = half3(N);
    surface.roughness = 1.0h;
    surface.metalness = 0.0h;
    surface.ao        = 1.0h;
    surface.emissive  = half3(0.0h);

    return buildFragmentOutput(surface, half4(outColor)
#ifdef OUTPUT_VELOCITY
        , in.currentClipPos, in.previousClipPos
#endif
        SATIN_ALPHA_OIT_FORWARD_ARGS
    );
}
