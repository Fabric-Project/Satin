public struct RenderPasses: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    // Phase 1
    public static let ssao       = RenderPasses(rawValue: 1 << 0)
    public static let taa        = RenderPasses(rawValue: 1 << 1)
    public static let motionBlur = RenderPasses(rawValue: 1 << 2)

    // Phase 2 (declared, not yet implemented)
    public static let ssr        = RenderPasses(rawValue: 1 << 3)
    public static let ssgi       = RenderPasses(rawValue: 1 << 4)
}
