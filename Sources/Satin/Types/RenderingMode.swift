public enum RenderingMode {
    /// Single color output. No auxiliary textures are allocated or written.
    case forward

    /// Full lighting computed per-material, auxiliary outputs (albedo, normals, PBR, velocity,
    /// emissive) written inline via MRT during the same geometry pass. Eliminates separate
    /// prepasses. Only enable outputs that are actually consumed by a post-processor — each
    /// active flag costs a texture allocation and a color attachment write per fragment.
    case forwardPlus

    /// Geometry pass writes surface properties to the G-buffer; lighting is resolved in a
    /// separate fullscreen deferred pass. Unlit materials always render in a subsequent forward
    /// pass regardless of this mode.
    case deferredGeometry
}
