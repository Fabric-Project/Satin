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

        injectShadowData(
            source: &source,
            receiveShadow: configuration.receiveShadow,
            shadowCount: configuration.shadowCount
        )

//      injectParametersArgs(
//            source: &source,
//            instancing: configuration.parameters
//        )

        injectShadowBuffer(
            source: &source,
            receiveShadow: configuration.receiveShadow,
            shadowCount: configuration.shadowCount
        )

        injectShadowFunction(
            source: &source,
            receiveShadow: configuration.receiveShadow,
            shadowCount: configuration.shadowCount
        )

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

        injectShadowCoords(
            source: &source,
            receiveShadow: configuration.receiveShadow,
            shadowCount: configuration.shadowCount
        )

        injectShadowVertexArgs(
            source: &source,
            receiveShadow: configuration.receiveShadow
        )

        injectShadowVertexCalc(
            source: &source,
            receiveShadow: configuration.receiveShadow,
            shadowCount: configuration.shadowCount
        )

        injectShadowFragmentArgs(
            source: &source,
            receiveShadow: configuration.receiveShadow,
            shadowCount: configuration.shadowCount
        )

        injectShadowFragmentCalc(
            source: &source,
            receiveShadow: configuration.receiveShadow,
            shadowCount: configuration.shadowCount
        )

        injectLightingArgs(
            source: &source,
            lighting: configuration.lighting
        )

        injectCustomCode(source: &source, configuration: configuration)

        queue.sync(flags: .barrier) {
            cache[configuration] = source
        }

//        print(source)

        return source
    }

}


extension ShaderLibrarySourceCache {
    private static let injectionRegistry = ShaderCodeInjectionRegistry<ShaderLibraryConfiguration>()

    // MARK: - Register Injector
    public static func registerInjector<T: ShaderCodeInjector>(_ injector: T, for materialType: String) where T.Configuration == ShaderLibraryConfiguration {
        injectionRegistry.register(injector, for: materialType)
    }

    public static func registerInjector(_ closure: @escaping @Sendable (inout String, ShaderLibraryConfiguration) -> Void, for materialType: String) {
        injectionRegistry.register(closure, for: materialType)
    }

    // MARK: - Unregister Injector
    public static func unregisterInjector(for materialType: String) {
        injectionRegistry.unregister(for: materialType)
    }

    // MARK: - Custom Injection
    private static func injectCustomCode(source: inout String, configuration: ShaderLibraryConfiguration) {
        injectionRegistry.injectCustomCode(source: &source, label: configuration.label, configuration: configuration)
    }
}
