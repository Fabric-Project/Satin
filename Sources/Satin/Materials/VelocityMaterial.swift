import Metal

public final class VelocityMaterial: Material {
    public required init(context: Context) {
        super.init(context: context)
        blending = .disabled
        // Re-rendering the same visible geometry against the forward-pass depth buffer.
        // Satin uses reversed-Z, so visible fragments are equal-or-greater than the stored
        // depth, while occluded geometry sits at smaller depth values.
        depthCompareFunction = .greaterEqual
        depthWriteEnabled = false
        // Nudge the second rasterization ~1 ULP closer so tiny FP differences between the
        // forward pass and velocity prepass do not punch holes into visible silhouettes.
        depthBias = DepthBias(bias: 1.0, slope: 1.0, clamp: 0.001)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
