//
//  Context.swift
//  Satin
//
//  Created by Reza Ali on 9/25/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal

public struct Context {
    public var id: UUID
    public var device: MTLDevice
    public var sampleCount: Int
    public var colorPixelFormat: MTLPixelFormat
    public var depthPixelFormat: MTLPixelFormat
    public var stencilPixelFormat: MTLPixelFormat
    public var vertexAmplificationCount: Int
    public var maxBuffersInFlight: Int

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
        lhs.sampleCount == rhs.sampleCount &&
            lhs.colorPixelFormat == rhs.colorPixelFormat &&
            lhs.depthPixelFormat == rhs.depthPixelFormat &&
            lhs.stencilPixelFormat == rhs.stencilPixelFormat &&
            lhs.vertexAmplificationCount == rhs.vertexAmplificationCount &&
            lhs.maxBuffersInFlight == rhs.maxBuffersInFlight
    }
}
