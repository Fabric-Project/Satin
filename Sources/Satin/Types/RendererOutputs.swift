public struct RendererOutputs: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let normals  = RendererOutputs(rawValue: 1 << 0)
    public static let velocity = RendererOutputs(rawValue: 1 << 1)
}
