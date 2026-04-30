//
//  ShaderLibrarySourceCache.swift
//
//
//  Created by Reza Ali on 6/14/23.
//

import Foundation

public final class ShaderLibrarySourceCache: Sendable {
    private nonisolated(unsafe) static var cache: [ShaderLibraryConfiguration: String] = [:]

    private static let queue = DispatchQueue(label: "ShaderLibrarySourceCacheQueue", attributes: .concurrent)

    static func invalidateLibrarySource(configuration: ShaderLibraryConfiguration) {
        queue.sync(flags: .barrier) {
            _ = cache.removeValue(forKey: configuration)
        }
    }

    static func getLibrarySource(configuration: ShaderLibraryConfiguration) throws -> String? {
        var cachedSource: String?

        queue.sync {
            cachedSource = cache[configuration]
        }

        if let cachedSource {
//            print("Returning Cached Shader Library Source: \n\(configuration)")
            return cachedSource
        }

//        print("Creating Shader Library Source: \(configuration)")

        guard let pipelineURL = configuration.pipelineURL,
              var source = RenderIncludeSource.get(),
              let shaderSource = try ShaderSourceCache.getSource(url: pipelineURL)
        else { return nil }

        injectDefines(
            source: &source,
            defines: configuration.defines
        )

        injectConstants(
            source: &source,
            constants: configuration.constants
        )

//      injectParametersArgs(
//            source: &source,
//            instancing: configuration.parameters
//        )

        injectVertex(
            source: &source,
            vertexDescriptor: configuration.vertexDescriptor
        )

        source += shaderSource

        injectPassThroughVertex(
            label: configuration.label,
            source: &source
        )

        if configuration.castShadow {
            injectPassThroughShadowVertex(
                label: configuration.label,
                source: &source
            )
        }

        injectInstancingArgs(
            source: &source,
            instancing: configuration.instancing
        )

//      injectUniformParametersArgs(
//            source: &source,
//            instancing: configuration.parameters
//        )

        injectLightingArgs(
            source: &source,
            lighting: configuration.lighting
        )

        injectDirectShadowArgs(
            source: &source,
            directShadowCount: configuration.directShadowCount,
            directShadowTextureCount: configuration.directShadowTextureCount
        )

        queue.sync(flags: .barrier) {
            cache[configuration] = source
        }

//        print(source)

        return source
    }
}
