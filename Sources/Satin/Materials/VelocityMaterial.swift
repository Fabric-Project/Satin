import Metal

public final class VelocityMaterial: Material {
    public required init(context: Context) {
        super.init(context: context)
        blending = .disabled
        // Re-rendering the same geometry after the forward pass: depths are equal, not strictly less.
        // Write nothing back to depth — we only need to cull occluded fragments.
        depthCompareFunction = .lessEqual
        depthWriteEnabled = false
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
