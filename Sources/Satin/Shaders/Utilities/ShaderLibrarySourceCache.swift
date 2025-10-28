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
    
    // MARK: - Custom Injector Registry
    public typealias ShaderInjectionClosure = @Sendable (inout String, ShaderLibraryConfiguration) -> Void
    private nonisolated(unsafe) static var injectors: [String: ShaderInjectionClosure] = [:]
    private static let injectorsQueue = DispatchQueue(label: "ShaderLibrarySourceCacheInjectorsQueue", attributes: .concurrent)

    // MARK: - Register Injector
    public static func registerInjector(_ injector: some ShaderCodeInjector, for materialType: String) {
        let closure: ShaderInjectionClosure = { source, config in
            injector.injectCode(source: &source, configuration: config)
        }
        injectorsQueue.sync(flags: .barrier) {
            injectors[materialType] = closure
        }
    }

    public static func registerInjector(_ closure: @escaping ShaderInjectionClosure, for materialType: String) {
        injectorsQueue.sync(flags: .barrier) {
            injectors[materialType] = closure
        }
    }

    // MARK: - Unregister Injector
    public static func unregisterInjector(for materialType: String) {
        injectorsQueue.sync(flags: .barrier) {
            _ = injectors.removeValue(forKey: materialType)
        }
    }

    // MARK: - Custom Injection
    private static func injectCustomCode(source: inout String, configuration: ShaderLibraryConfiguration) {
        var availableInjectors: [String: ShaderInjectionClosure] = [:]

        injectorsQueue.sync {
            availableInjectors = injectors
        }

        // Material-specific injector
        if let injector = availableInjectors[configuration.label] {
            injector(&source, configuration)
        }

        // Global injector (wildcard)
        if let globalInjector = availableInjectors["*"] {
            globalInjector(&source, configuration)
        }
    }
}

// MARK: - Shader Code Injector
public protocol ShaderCodeInjector: Sendable {
    func injectCode(source: inout String, configuration: ShaderLibraryConfiguration)
}
