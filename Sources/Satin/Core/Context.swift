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

    public init(id: UUID = UUID(),
                device: MTLDevice,
                sampleCount: Int,
                colorPixelFormat: MTLPixelFormat,
                depthPixelFormat: MTLPixelFormat = .invalid,
                stencilPixelFormat: MTLPixelFormat = .invalid,
                vertexAmplificationCount: Int = 1,
                maxBuffersInFlight: Int = Satin.maxBuffersInFlight)
    {
        self.id = id
        self.device = device
        self.sampleCount = sampleCount
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.stencilPixelFormat = stencilPixelFormat
        self.vertexAmplificationCount = vertexAmplificationCount
        self.maxBuffersInFlight = maxBuffersInFlight
    }

    func getDefines() -> [ShaderDefine] {
        var defines = [ShaderDefine]()
        if vertexAmplificationCount > 1 {
            defines.append(ShaderDefine(key: "LAYERED", value: NSString(string: "true")))
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
            lhs.maxBuffersInFlight == rhs.maxBuffersInFlight
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
