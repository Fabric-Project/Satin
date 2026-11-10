//
//  PointSprite.swift
//  Satin
//

import Metal
import simd

/// How a material shapes each point it draws. It applies only to points: a mesh of triangles
/// drawn with the same material draws as it always does. Shaders take it with
/// `SATIN_POINT_SPRITE_FRAGMENT_DATA` and `SATIN_POINT_SPRITE(color)`; see `PointSprite.metal`.
public enum PointSprite: Hashable, Sendable {
    /// Square points, as Metal draws them.
    case square
    /// A round point, its edge softened by `Material.pointSpriteSoftness`, with no texture.
    case disc
    /// Each point samples `Material.pointSpriteTexture` across it.
    case texture
}

/// What the point sprite chunk reads at `FragmentBufferIndex.PointSprite`.
struct PointSpriteUniforms {
    var textureTransform: simd_float4x4
    var softness: Float
}
