import Metal

public final class VelocityMaterial: Material {
    public required init(context: Context) {
        super.init(context: context)
        blending = .disabled
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
