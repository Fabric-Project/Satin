//
//  Context.swift
//  Satin
//
//  Created by Reza Ali on 9/25/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal

public struct Context {
    public let id: UUID
    public let device: MTLDevice
    public let commandQueue:MTLCommandQueue
    public let sampleCount: Int
    public let colorPixelFormat: MTLPixelFormat
    public let depthPixelFormat: MTLPixelFormat
    public let stencilPixelFormat: MTLPixelFormat
    public let vertexAmplificationCount: Int
    public let maxBuffersInFlight: Int

    // Rendering mode and active auxiliary outputs. Switching renderingMode at runtime causes
    // pipeline states to recompile on the next frame — avoid toggling per-frame.
    public let renderingMode: RenderingMode
    public let activeOutputs: RendererOutputs
    public let alphaOitEnabled: Bool

    // Pixel formats for each auxiliary G-buffer attachment. These must match the formats used
    // when creating the corresponding textures on the renderer — both the pipeline descriptor
    // (compiled from Context) and the render pass descriptor (texture creation) read from here.
    public let albedoPixelFormat: MTLPixelFormat
    public let normalsPixelFormat: MTLPixelFormat
    public let pbrPixelFormat: MTLPixelFormat
    public let velocityPixelFormat: MTLPixelFormat
    public let emissivePixelFormat: MTLPixelFormat

    public init(
        id: UUID = UUID(),
        device: MTLDevice,
        sampleCount: Int,
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat = .invalid,
        stencilPixelFormat: MTLPixelFormat = .invalid,
        vertexAmplificationCount: Int = 1,
        maxBuffersInFlight: Int = Satin.maxBuffersInFlight,
        renderingMode: RenderingMode = .forward,
        activeOutputs: RendererOutputs = [.color],
        alphaOitEnabled: Bool = false,
        albedoPixelFormat: MTLPixelFormat = .bgra8Unorm,
        normalsPixelFormat: MTLPixelFormat = .rgba16Float,
        pbrPixelFormat: MTLPixelFormat = .rgba8Unorm,
        velocityPixelFormat: MTLPixelFormat = .rg16Float,
        emissivePixelFormat: MTLPixelFormat = .rgba16Float
    ) {
        self.id = id
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.stencilPixelFormat = stencilPixelFormat
        self.vertexAmplificationCount = vertexAmplificationCount
        self.maxBuffersInFlight = maxBuffersInFlight
        self.renderingMode = renderingMode
        self.activeOutputs = activeOutputs
        self.alphaOitEnabled = alphaOitEnabled
        self.albedoPixelFormat = albedoPixelFormat
        self.normalsPixelFormat = normalsPixelFormat
        self.pbrPixelFormat = pbrPixelFormat
        self.velocityPixelFormat = velocityPixelFormat
        self.emissivePixelFormat = emissivePixelFormat
    }

    func getDefines() -> [ShaderDefine] {
        var defines = [ShaderDefine]()
        if vertexAmplificationCount > 1 {
            defines.append(ShaderDefine(key: "LAYERED", value: NSString(string: "true")))
        }
        if activeOutputs.contains(.albedo)   { defines.append(ShaderDefine(key: "OUTPUT_ALBEDO",   value: NSString(string: "1"))) }
        if activeOutputs.contains(.normals)  { defines.append(ShaderDefine(key: "OUTPUT_NORMALS",  value: NSString(string: "1"))) }
        if activeOutputs.contains(.pbr)      { defines.append(ShaderDefine(key: "OUTPUT_PBR",      value: NSString(string: "1"))) }
        if activeOutputs.contains(.velocity) { defines.append(ShaderDefine(key: "OUTPUT_VELOCITY", value: NSString(string: "1"))) }
        if activeOutputs.contains(.emissive) { defines.append(ShaderDefine(key: "OUTPUT_EMISSIVE", value: NSString(string: "1"))) }
        if alphaOitEnabled {
            defines.append(ShaderDefine(key: "ALPHA_OIT", value: NSString(string: "1")))
        }
        switch renderingMode {
        case .deferredGeometry: defines.append(ShaderDefine(key: "DEFERRED_GEOMETRY", value: NSString(string: "1")))
        case .forwardPlus:      defines.append(ShaderDefine(key: "FORWARD_PLUS",      value: NSString(string: "1")))
        case .forward:          break
        }
        return defines
    }
}

extension Context: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(ObjectIdentifier(device))
        hasher.combine(sampleCount)
        hasher.combine(colorPixelFormat)
        hasher.combine(depthPixelFormat)
        hasher.combine(stencilPixelFormat)
        hasher.combine(vertexAmplificationCount)
        hasher.combine(maxBuffersInFlight)
        hasher.combine(renderingMode)
        hasher.combine(activeOutputs)
        hasher.combine(alphaOitEnabled)
        hasher.combine(albedoPixelFormat)
        hasher.combine(normalsPixelFormat)
        hasher.combine(pbrPixelFormat)
        hasher.combine(velocityPixelFormat)
        hasher.combine(emissivePixelFormat)
    }
}

extension Context: Equatable {
    public static func == (lhs: Context, rhs: Context) -> Bool {
        lhs.id == rhs.id &&
            lhs.device === rhs.device &&
            lhs.sampleCount == rhs.sampleCount &&
            lhs.colorPixelFormat == rhs.colorPixelFormat &&
            lhs.depthPixelFormat == rhs.depthPixelFormat &&
            lhs.stencilPixelFormat == rhs.stencilPixelFormat &&
            lhs.vertexAmplificationCount == rhs.vertexAmplificationCount &&
            lhs.maxBuffersInFlight == rhs.maxBuffersInFlight &&
            lhs.renderingMode == rhs.renderingMode &&
            lhs.activeOutputs == rhs.activeOutputs &&
            lhs.alphaOitEnabled == rhs.alphaOitEnabled &&
            lhs.albedoPixelFormat == rhs.albedoPixelFormat &&
            lhs.normalsPixelFormat == rhs.normalsPixelFormat &&
            lhs.pbrPixelFormat == rhs.pbrPixelFormat &&
            lhs.velocityPixelFormat == rhs.velocityPixelFormat &&
            lhs.emissivePixelFormat == rhs.emissivePixelFormat
    }
}

public extension Context {
    /// Creates a Context with platform-appropriate defaults, using the system default Metal device.
    ///
    /// - macOS / iOS / tvOS: `bgra8Unorm` color, `depth32Float` depth, sampleCount 1
    /// - visionOS device:    `bgra8Unorm_srgb` color, `depth32Float` depth, sampleCount 1, vertexAmplificationCount 2
    /// - visionOS simulator: same as device but vertexAmplificationCount 1 (dedicated layout)
    ///
    /// Pass an explicit `device` to override device selection; all other parameters use
    /// the platform defaults above. For full control — custom pixel formats, MSAA, deferred
    /// rendering, alpha OIT — construct a `Context` directly.
    static func makePlatformDefault(device: MTLDevice? = nil) -> Context {
        let d = device ?? MTLCreateSystemDefaultDevice()!
#if os(visionOS)
#if targetEnvironment(simulator)
        return Context(device: d, sampleCount: 1, colorPixelFormat: .bgra8Unorm_srgb,
                       depthPixelFormat: .depth32Float, vertexAmplificationCount: 1)
#else
        return Context(device: d, sampleCount: 1, colorPixelFormat: .bgra8Unorm_srgb,
                       depthPixelFormat: .depth32Float, vertexAmplificationCount: 2)
#endif
#else
        return Context(device: d, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
#endif
    }
}

extension CodingUserInfoKey {
    public static let satinContext = CodingUserInfoKey(rawValue: "Satin.Context")!
}

extension Decoder {
    public var satinContext: Context? {
        userInfo[.satinContext] as? Context
    }

    public func requireSatinContext(typeName: String) throws -> Context {
        guard let context = satinContext else {
            let description = "\(typeName) decoding requires Decoder.userInfo[.satinContext]"
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: description))
        }
        return context
    }
}
