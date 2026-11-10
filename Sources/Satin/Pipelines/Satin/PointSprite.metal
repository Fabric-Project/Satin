// Point sprites: how a material shapes each point it draws (`Material.pointSprite`).
//
// A material's fragment shader opts in with two macros:
// 1. `SATIN_POINT_SPRITE_FRAGMENT_DATA` at the end of its arguments, before
//    `SATIN_ALPHA_OIT_FRAGMENT_DATA` when it has both.
// 2. `SATIN_POINT_SPRITE(color)` around its base color, a float4 or half4, before lighting.
//
// Both expand to nothing unless the draw is of points (`SATIN_POINT_PRIMITIVE`, set per draw
// layout) and the material asks for a disc or a texture, so meshes of triangles pay nothing.
// A sprite multiplies the color, alpha included, and discards what it leaves fully transparent,
// so an unblended material still draws round points.

typedef struct {
    float4x4 textureTransform;
    float softness;
} PointSpriteUniforms;

#if defined(SATIN_POINT_PRIMITIVE) && defined(SATIN_POINT_SPRITE_TEXTURE)
#define SATIN_POINT_SPRITE_ENABLED 1
#define SATIN_POINT_SPRITE_FRAGMENT_DATA , float2 satinPointCoord [[point_coord]], constant PointSpriteUniforms &satinPointSprite [[buffer(FragmentBufferPointSprite)]], texture2d<float> satinPointSpriteTexture [[texture(FragmentTexturePointSprite)]]
#define SATIN_POINT_SPRITE(color) satinPointSpriteTextured((color), satinPointCoord, satinPointSprite, satinPointSpriteTexture)
#elif defined(SATIN_POINT_PRIMITIVE) && defined(SATIN_POINT_SPRITE_DISC)
#define SATIN_POINT_SPRITE_ENABLED 1
#define SATIN_POINT_SPRITE_FRAGMENT_DATA , float2 satinPointCoord [[point_coord]], constant PointSpriteUniforms &satinPointSprite [[buffer(FragmentBufferPointSprite)]]
#define SATIN_POINT_SPRITE(color) satinPointSpriteDisc((color), satinPointCoord, satinPointSprite)
#else
#define SATIN_POINT_SPRITE_FRAGMENT_DATA
#define SATIN_POINT_SPRITE(color) (color)
#endif

// Fragment-only helpers, compiled only where a sprite applies.
#if defined(SATIN_POINT_SPRITE_ENABLED)
// A disc: opaque inside, fading over `softness` of its radius, antialiased at its edge.
inline float satinPointSpriteDiscCoverage(float2 pointCoord, constant PointSpriteUniforms &sprite) {
    const float distance = length(pointCoord - 0.5) * 2.0;
    const float edge = max(saturate(sprite.softness), fwidth(distance));
    return 1.0 - smoothstep(1.0 - edge, 1.0, distance);
}

inline float4 satinPointSpriteKeep(float4 color) {
    if (color.a <= 0.0) { discard_fragment(); }
    return color;
}

inline float4 satinPointSpriteDisc(float4 color, float2 pointCoord, constant PointSpriteUniforms &sprite) {
    return satinPointSpriteKeep(float4(color.rgb, color.a * satinPointSpriteDiscCoverage(pointCoord, sprite)));
}

inline half4 satinPointSpriteDisc(half4 color, float2 pointCoord, constant PointSpriteUniforms &sprite) {
    return half4(satinPointSpriteDisc(float4(color), pointCoord, sprite));
}

inline float4 satinPointSpriteTextured(float4 color, float2 pointCoord, constant PointSpriteUniforms &sprite, texture2d<float> spriteTexture) {
    constexpr sampler spriteSampler(min_filter::linear, mag_filter::linear, mip_filter::linear);
    const float2 uv = (sprite.textureTransform * float4(pointCoord, 0.0, 1.0)).xy;
    return satinPointSpriteKeep(color * spriteTexture.sample(spriteSampler, uv));
}

inline half4 satinPointSpriteTextured(half4 color, float2 pointCoord, constant PointSpriteUniforms &sprite, texture2d<float> spriteTexture) {
    return half4(satinPointSpriteTextured(float4(color), pointCoord, sprite, spriteTexture));
}
#endif
