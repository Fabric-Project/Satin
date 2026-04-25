//
//  ShaderLibraryConfiguration.swift
//
//
//  Created by Reza Ali on 6/14/23.
//

import Foundation
import Metal

// these are things that change the library source code
public struct ShaderLibraryConfiguration {
    var label: String

    var libraryURL: URL?
    var pipelineURL: URL?

    var vertexDescriptor: MTLVertexDescriptor

    // Instancing
    var instancing: Bool

    // Lighting
    var lighting: Bool

    // Shadows
    var castShadow: Bool
    var receiveShadow: Bool
    var shadowCount: Int

    var defines: [ShaderDefine]
    var constants: [String]
}

extension ShaderLibraryConfiguration: Equatable {
    public static func == (lhs: ShaderLibraryConfiguration, rhs: ShaderLibraryConfiguration) -> Bool {
        lhs.label == rhs.label &&
            lhs.libraryURL == rhs.libraryURL &&
            lhs.pipelineURL == rhs.pipelineURL &&
            lhs.vertexDescriptor == rhs.vertexDescriptor &&
            lhs.instancing == rhs.instancing &&
            lhs.lighting == rhs.lighting &&
            lhs.castShadow == rhs.castShadow &&
            lhs.receiveShadow == rhs.receiveShadow &&
            lhs.shadowCount == rhs.shadowCount &&
            lhs.defines == rhs.defines &&
            lhs.constants == rhs.constants
    }
}

extension ShaderLibraryConfiguration: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)

        if let libraryURL = libraryURL { hasher.combine(libraryURL) }
        if let pipelineURL = pipelineURL { hasher.combine(pipelineURL) }

        hasher.combine(vertexDescriptor)
        hasher.combine(instancing)
        hasher.combine(lighting)

        hasher.combine(castShadow)
        hasher.combine(receiveShadow)
        hasher.combine(shadowCount)

        if !defines.isEmpty { hasher.combine(defines) }
        if !constants.isEmpty { hasher.combine(constants) }
    }
}
