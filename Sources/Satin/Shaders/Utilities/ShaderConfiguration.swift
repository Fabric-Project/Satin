//
//  ShaderConfiguration.swift
//
//
//  Created by Reza Ali on 6/14/23.
//

import Foundation
import Metal

public struct ShaderConfiguration {
    public internal(set) var context: Context?

    // Information
    public internal(set) var label: String

    public internal(set) var vertexFunctionName: String
    public internal(set) var fragmentFunctionName: String
    public internal(set) var shadowFunctionName: String

    // URLs
    public internal(set) var libraryURL: URL? // this is where we get the MTLLibrary from file and build from there
    public internal(set) var pipelineURL: URL? // this is where we get the pipeline source from file and build from there

    public internal(set) var rendering = RenderingConfiguration()

    public internal(set) var defines: [ShaderDefine] = []
    public internal(set) var constants: [String] = []

    public var blending: ShaderBlending {
        rendering.blending
    }

    public init(label: String = "",
                vertexFunctionName: String = "",
                fragmentFunctionName: String = "",
                shadowFunctionName: String = "",
                libraryURL: URL? = nil,
                pipelineURL: URL? = nil)
    {
        self.label = label
        self.vertexFunctionName = vertexFunctionName
        self.fragmentFunctionName = fragmentFunctionName
        self.shadowFunctionName = shadowFunctionName
        self.libraryURL = libraryURL
        self.pipelineURL = pipelineURL
    }

    public func getLibraryConfiguration() -> ShaderLibraryConfiguration {
        var resolvedDefines = defines + rendering.getDefines()
        if let context {
            resolvedDefines += context.getDefines()
        }

        let resolvedConstants = constants + rendering.getConstants()

        return ShaderLibraryConfiguration(
            label: label,
            libraryURL: libraryURL,
            pipelineURL: pipelineURL,
            vertexDescriptor: rendering.vertexDescriptor,
            instancing: rendering.instancing,
            lighting: rendering.lighting,
            castShadow: rendering.castShadow,
            receiveShadow: rendering.receiveShadow,
            shadowCount: rendering.shadowCount,
            defines: resolvedDefines,
            constants: resolvedConstants
        )
    }
}

extension ShaderConfiguration: Equatable {
    public static func == (lhs: ShaderConfiguration, rhs: ShaderConfiguration) -> Bool {
        var contextPipelineEquivalence = true
        if let lhsContext = lhs.context, let rhsContext = rhs.context {
            contextPipelineEquivalence =
                lhsContext.sampleCount == rhsContext.sampleCount &&
                lhsContext.colorPixelFormat == rhsContext.colorPixelFormat &&
                lhsContext.depthPixelFormat == rhsContext.depthPixelFormat &&
                lhsContext.stencilPixelFormat == rhsContext.stencilPixelFormat &&
                lhsContext.vertexAmplificationCount == rhsContext.vertexAmplificationCount
        }

        return contextPipelineEquivalence &&
            lhs.label == rhs.label &&
            lhs.vertexFunctionName == rhs.vertexFunctionName &&
            lhs.fragmentFunctionName == rhs.fragmentFunctionName &&
            lhs.shadowFunctionName == rhs.shadowFunctionName &&
            lhs.libraryURL == rhs.libraryURL &&
            lhs.pipelineURL == rhs.pipelineURL &&
            lhs.defines == rhs.defines &&
            lhs.constants == rhs.constants &&
            lhs.rendering == rhs.rendering
    }
}

extension ShaderConfiguration: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)

        if !vertexFunctionName.isEmpty { hasher.combine(vertexFunctionName) }
        if !fragmentFunctionName.isEmpty { hasher.combine(fragmentFunctionName) }
        if !shadowFunctionName.isEmpty { hasher.combine(shadowFunctionName) }

        if let libraryURL = libraryURL { hasher.combine(libraryURL) }
        if let pipelineURL = pipelineURL { hasher.combine(pipelineURL) }

        hasher.combine(defines)
        hasher.combine(constants)
        hasher.combine(rendering)
    }
}

extension ShaderConfiguration: CustomStringConvertible {
    public var description: String {
        var output = "\n"
        output += "\t Label: \(label)\n"
        output += "\t Context: \(context == nil ? "nil" : "valid")\n"
        output += "\t VertexName: \(vertexFunctionName)\n"
        output += "\t FragmentName: \(fragmentFunctionName)\n"
        output += "\t ShadowName: \(shadowFunctionName)\n"
        output += "\t Defines: \(defines)\n"
        output += "\t Constants: \(constants)\n"
        if let libraryURL = libraryURL { output += "\t libraryURL: \(libraryURL.relativePath)\n" }
        if let pipelineURL = pipelineURL { output += "\t pipelineURL: \(pipelineURL.relativePath)\n" }
        output += "\t \(rendering.description)"
        return output
    }
}
