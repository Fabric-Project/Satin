import Satin
import simd

/// `matrix` split by `decomposed` and composed again; equal to `matrix` when it has no shear.
func recomposed(_ matrix: simd_float4x4) -> simd_float4x4 {
    let decomposition = matrix.decomposed
    return simd_float4x4(translation: decomposition.translation, rotation: decomposition.rotation, scale: decomposition.scale)
}
