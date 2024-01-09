//
//  ComputeShaderLibraryConfiguration.swift
//
//
//  Created by Reza Ali on 1/8/24.
//

import Foundation

// these are things that change the library source code
public struct ComputeShaderLibraryConfiguration {
    var label: String

    var libraryURL: URL?
    var pipelineURL: URL?

    var defines: [ShaderDefine]
    var constants: [String]
}

extension ComputeShaderLibraryConfiguration: Equatable {
    public static func == (lhs: ComputeShaderLibraryConfiguration, rhs: ComputeShaderLibraryConfiguration) -> Bool {
        lhs.label == rhs.label &&
            lhs.libraryURL == rhs.libraryURL &&
            lhs.pipelineURL == rhs.pipelineURL &&
            lhs.defines == rhs.defines &&
            lhs.constants == rhs.constants
    }
}

extension ComputeShaderLibraryConfiguration: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)

        if let libraryURL = libraryURL { hasher.combine(libraryURL) }
        if let pipelineURL = pipelineURL { hasher.combine(pipelineURL) }

        if !defines.isEmpty { hasher.combine(defines) }
        if !constants.isEmpty { hasher.combine(constants) }
    }
}
