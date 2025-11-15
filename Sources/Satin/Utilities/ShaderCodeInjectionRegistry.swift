//
//  ShaderCodeInjectionRegistry.swift
//
//
//  Created by Reza Ali on 1/15/25.
//

import Foundation

// MARK: - Shader Code Injector Protocol
public protocol ShaderCodeInjector: Sendable {
    associatedtype Configuration
    func injectCode(source: inout String, configuration: Configuration)
}

// MARK: - Generic Injection Registry
public final class ShaderCodeInjectionRegistry<Configuration>: Sendable {
    public typealias InjectionClosure = @Sendable (inout String, Configuration) -> Void

    private nonisolated(unsafe) var injectors: [String: InjectionClosure] = [:]
    private let queue = DispatchQueue(label: "ShaderCodeInjectionRegistryQueue", attributes: .concurrent)

    public init() {}

    // MARK: - Register Injector
    public func register<T: ShaderCodeInjector>(_ injector: T, for key: String) where T.Configuration == Configuration {
        let closure: InjectionClosure = { source, config in
            injector.injectCode(source: &source, configuration: config)
        }
        queue.sync(flags: .barrier) {
            injectors[key] = closure
        }
    }

    public func register(_ closure: @escaping InjectionClosure, for key: String) {
        queue.sync(flags: .barrier) {
            injectors[key] = closure
        }
    }

    // MARK: - Unregister Injector
    public func unregister(for key: String) {
        queue.sync(flags: .barrier) {
            _ = injectors.removeValue(forKey: key)
        }
    }

    // MARK: - Inject Custom Code
    public func injectCustomCode(source: inout String, label: String, configuration: Configuration) {
        var availableInjectors: [String: InjectionClosure] = [:]

        queue.sync {
            availableInjectors = injectors
        }

        // Label-specific injector
        if let injector = availableInjectors[label] {
            injector(&source, configuration)
        }

        // Global injector (wildcard)
        if let globalInjector = availableInjectors["*"] {
            globalInjector(&source, configuration)
        }
    }
}
