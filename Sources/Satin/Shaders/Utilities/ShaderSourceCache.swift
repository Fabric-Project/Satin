//
//  PipelineSources.swift
//  Satin
//
//  Created by Reza Ali on 3/3/23.
//

import Foundation

public final class ShaderSourceCache: Sendable {
    private struct CachedSource {
        let text: String
        let definesAlphaOrderIndependentTransparency: Bool

        init(text: String) {
            self.text = text
            definesAlphaOrderIndependentTransparency = text.contains("#define SATIN_ALPHA_OIT_ENABLED")
        }
    }

    private nonisolated(unsafe) static var sourceCache: [URL: CachedSource] = [:]
    private nonisolated(unsafe) static var compilerCache: [URL: MetalFileCompiler] = [:]

    private static let sourceQueue = DispatchQueue(label: "ShaderSourceCacheSourceQueue", attributes: .concurrent)
    private static let compilerQueue = DispatchQueue(label: "ShaderSourceCacheCompilerQueue", attributes: .concurrent)

    public static func removeSource(url: URL) {
        sourceQueue.sync(flags: .barrier) {
            _ = sourceCache.removeValue(forKey: url)
        }
    }

    public static func getSource(url: URL) throws -> String? {
        try getCachedSource(url: url).text
    }

    static func definesAlphaOrderIndependentTransparency(url: URL) throws -> Bool {
        try getCachedSource(url: url).definesAlphaOrderIndependentTransparency
    }

    private static func getCachedSource(url: URL) throws -> CachedSource {
        if let cachedSource = sourceQueue.sync(execute: { sourceCache[url] }) {
            return cachedSource
        }
        return try sourceQueue.sync(flags: .barrier) {
            if let cachedSource = sourceCache[url] {
                return cachedSource
            }
            let cachedSource = CachedSource(text: try getCompiler(url: url).parse(url))
            sourceCache[url] = cachedSource
            return cachedSource
        }
    }

    public static func getCompiler(url: URL) -> MetalFileCompiler {
        var cachedCompiler: MetalFileCompiler?

        compilerQueue.sync { // Read
            cachedCompiler = compilerCache[url]
        }

        if let cachedCompiler {
            return cachedCompiler
        }

        let compiler = MetalFileCompiler(watch: false)

        compilerQueue.sync(flags: .barrier) {
            compilerCache[url] = compiler
        }

        return compiler
    }
}

public final class PassThroughVertexPipelineSource: Sendable {
    static let shared = PassThroughVertexPipelineSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesCommonURL("VertexShader.metal")
    private static let queue = DispatchQueue(label: "PassThroughVertexPipelineSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class PassThroughShadowPipelineSource: Sendable {
    static let shared = PassThroughShadowPipelineSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesCommonURL("ShadowShader.metal")
    private static let queue = DispatchQueue(label: "PassThroughShadowPipelineSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class ShadowFunctionSource: Sendable {
    static let shared = ShadowFunctionSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesLibraryURL("Shadow.metal")
    private static let queue = DispatchQueue(label: "ShadowFunctionSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class ConstantsSource: Sendable {
    static let shared = ConstantsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("Constants.metal")
    private static let queue = DispatchQueue(label: "ConstantsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class ComputeConstantsSource: Sendable {
    static let shared = ComputeConstantsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("ComputeConstants.metal")
    private static let queue = DispatchQueue(label: "ComputeConstantsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class MeshConstantsSource: Sendable {
    static let shared = MeshConstantsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("MeshConstants.metal")
    private static let queue = DispatchQueue(label: "MeshConstantsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class VertexConstantsSource: Sendable {
    static let shared = VertexConstantsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("VertexConstants.metal")
    private static let queue = DispatchQueue(label: "VertexConstantsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class FragmentConstantsSource: Sendable {
    static let shared = FragmentConstantsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("FragmentConstants.metal")
    private static let queue = DispatchQueue(label: "FragmentConstantsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class PBRConstantsSource: Sendable {
    static let shared = PBRConstantsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("PBRConstants.metal")
    private static let queue = DispatchQueue(label: "PBRConstantsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class RenderIncludeSource: Sendable {
    static let shared = RenderIncludeSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("RenderIncludes.metal")
    private static let queue = DispatchQueue(label: "RenderIncludeSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class ComputeIncludeSource: Sendable {
    static let shared = ComputeIncludeSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("ComputeIncludes.metal")
    private static let queue = DispatchQueue(label: "ComputeIncludeSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class VertexSource: Sendable {
    static let shared = VertexSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("Vertex.metal")
    private static let queue = DispatchQueue(label: "VertexSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class VertexDataSource: Sendable {
    static let shared = VertexDataSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("VertexData.metal")
    private static let queue = DispatchQueue(label: "VertexDataSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class VertexUniformsSource: Sendable {
    static let shared = VertexUniformsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("VertexUniforms.metal")
    private static let queue = DispatchQueue(label: "VertexUniformsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class InstanceMatrixUniformsSource: Sendable {
    static let shared = InstanceMatrixUniformsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("InstanceMatrixUniforms.metal")
    private static let queue = DispatchQueue(label: "InstanceMatrixUniformsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class LightingSource: Sendable {
    static let shared = LightingSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("LightData.metal")
    private static let queue = DispatchQueue(label: "LightingSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class ShadowDataSource: Sendable {
    static let shared = ShadowDataSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("ShadowData.metal")
    private static let queue = DispatchQueue(label: "ShadowDataSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}

public final class InstancingArgsSource: Sendable {
    static let shared = InstancingArgsSource()
    private nonisolated(unsafe) static var sharedSource: String?

    private static let url = getPipelinesSatinURL("InstancingArgs.metal")
    private static let queue = DispatchQueue(label: "InstancingArgsSourceQueue", attributes: .concurrent)

    public static func get() -> String? {
        var source: String?

        queue.sync {
            source = self.sharedSource
        }

        if let source {
            return source
        }

        guard let url else { return nil }

        do {
            let source = try MetalFileCompiler(watch: false).parse(url)
            queue.sync(flags: .barrier) {
                self.sharedSource = source
            }
            return source
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}
