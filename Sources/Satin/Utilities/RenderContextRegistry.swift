//
//  RenderContextRegistry.swift
//  Satin
//

import Metal

/// Gives every distinct render context configuration a small integer, `Context.index`, so a
/// per-draw pipeline lookup reads an array instead of hashing a context. Contexts are interned by
/// everything a pipeline depends on: the device, sample count, every attachment format, the
/// amplification count, rendering mode, outputs and OIT. Equal configurations share one index for
/// the life of the process; different devices never do. An app makes a handful, and a lookup runs
/// only when a `Context` is created, so configurations are compared in turn rather than hashed.
enum RenderContextRegistry {
    struct Configuration {
        let device: MTLDevice
        let sampleCount: Int
        let colorPixelFormat: MTLPixelFormat
        let depthPixelFormat: MTLPixelFormat
        let stencilPixelFormat: MTLPixelFormat
        let vertexAmplificationCount: Int
        let renderingMode: RenderingMode
        let activeOutputs: RendererOutputs
        let alphaOitEnabled: Bool
        let albedoPixelFormat: MTLPixelFormat
        let normalsPixelFormat: MTLPixelFormat
        let pbrPixelFormat: MTLPixelFormat
        let velocityPixelFormat: MTLPixelFormat
        let emissivePixelFormat: MTLPixelFormat

        func matches(_ other: Configuration) -> Bool {
            device === other.device &&
                sampleCount == other.sampleCount &&
                colorPixelFormat == other.colorPixelFormat &&
                depthPixelFormat == other.depthPixelFormat &&
                stencilPixelFormat == other.stencilPixelFormat &&
                vertexAmplificationCount == other.vertexAmplificationCount &&
                renderingMode == other.renderingMode &&
                activeOutputs == other.activeOutputs &&
                alphaOitEnabled == other.alphaOitEnabled &&
                albedoPixelFormat == other.albedoPixelFormat &&
                normalsPixelFormat == other.normalsPixelFormat &&
                pbrPixelFormat == other.pbrPixelFormat &&
                velocityPixelFormat == other.velocityPixelFormat &&
                emissivePixelFormat == other.emissivePixelFormat
        }
    }

    private static let lock = UnfairLock()
    private nonisolated(unsafe) static var configurations: [Configuration] = []

    static func index(for configuration: Configuration) -> Int {
        lock.sync {
            if let index = configurations.firstIndex(where: { $0.matches(configuration) }) { return index }

            configurations.append(configuration)
            return configurations.count - 1
        }
    }

    /// How many distinct configurations have been interned: it grows with configurations, never
    /// with frames.
    static var count: Int {
        lock.sync { configurations.count }
    }
}
