/// Bitmask controlling which G-buffer attachments the renderer produces each frame.
///
/// Bit position N maps directly to Metal color attachment index N, and to the corresponding
/// `ATTACHMENT_*` constant in `Includes/RendererAttachments.metal`. The two must stay in sync.
public struct RendererOutputs: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let color    = RendererOutputs(rawValue: 1 << 0) // attachment 0 — always present
    public static let albedo   = RendererOutputs(rawValue: 1 << 1) // attachment 1
    public static let normals  = RendererOutputs(rawValue: 1 << 2) // attachment 2
    public static let pbr      = RendererOutputs(rawValue: 1 << 3) // attachment 3 — roughness/metalness/AO
    public static let velocity = RendererOutputs(rawValue: 1 << 4) // attachment 4
    public static let emissive = RendererOutputs(rawValue: 1 << 5) // attachment 5
}
