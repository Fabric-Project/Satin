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
        albedoPixelFormat: MTLPixelFormat = .bgra8Unorm,
        normalsPixelFormat: MTLPixelFormat = .rgba16Float,
        pbrPixelFormat: MTLPixelFormat = .rgba8Unorm,
        velocityPixelFormat: MTLPixelFormat = .rg16Float,
        emissivePixelFormat: MTLPixelFormat = .rgba16Float
    ) {
        self.id = id
        self.device = device
        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.stencilPixelFormat = stencilPixelFormat
        self.vertexAmplificationCount = vertexAmplificationCount
        self.maxBuffersInFlight = maxBuffersInFlight
        self.renderingMode = renderingMode
        self.activeOutputs = activeOutputs
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
        switch renderingMode {
        case .deferredGeometry: defines.append(ShaderDefine(key: "DEFERRED_GEOMETRY", value: NSString(string: "1")))
        case .forwardPlus:      defines.append(ShaderDefine(key: "FORWARD_PLUS",      value: NSString(string: "1")))
        case .forward:          break
        }
        return defines
    }
}

extension Context: Hashable {
    // id is a UUID assigned once at init and never changes — it uniquely identifies
    // this Context instance, so hashing only id avoids hashing 14 fields including
    // multiple MTLPixelFormat RawRepresentables through protocol witness chains.
    // This matters in the hot render loop where Context is used as a dictionary key
    // on every pipeline lookup and vertex-uniform lookup (including 6x per point shadow face).
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Context: Equatable {
    public static func == (lhs: Context, rhs: Context) -> Bool {
        lhs.id == rhs.id
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
