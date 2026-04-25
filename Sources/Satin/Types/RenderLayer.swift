public struct RenderLayer: RawRepresentable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let opaque      = RenderLayer(rawValue: 0)
    public static let transparent = RenderLayer(rawValue: 1)
    public static let overlay     = RenderLayer(rawValue: 2)
}
