//
//  ShaderLibraryCache.swift
//
//
//  Created by Reza Ali on 6/14/23.
//

import Foundation
import Metal

public final class ShaderLibraryCache: Sendable {
    private nonisolated(unsafe) static var cache: [ShaderLibraryConfiguration: MTLLibrary] = [:]
    private nonisolated(unsafe) static var defaultLibrary: MTLLibrary?

    private static let defaultLibraryQueue = DispatchQueue(label: "ShaderLibraryCacheDefaultLibraryQueue", attributes: .concurrent)
    private static let libraryQueue = DispatchQueue(label: "ShaderLibraryCacheQueue", attributes: .concurrent)

    public static func invalidateLibrary(configuration: ShaderLibraryConfiguration) {
        libraryQueue.sync(flags: .barrier) {
            _ = cache.removeValue(forKey: configuration)
        }
    }

    public static func getDefaultLibrary(device: MTLDevice) -> MTLLibrary? {
        var library: MTLLibrary?

        defaultLibraryQueue.sync {
            library = self.defaultLibrary
        }

        if let library {
            return library
        }

        library = device.makeDefaultLibrary()

        defaultLibraryQueue.sync(flags: .barrier) {
            self.defaultLibrary = library
        }

        return library
    }

    public static func getLibrary(configuration: ShaderLibraryConfiguration, device: MTLDevice) throws -> MTLLibrary? {
        var library: MTLLibrary?

        libraryQueue.sync {
            library = self.cache[configuration]
        }

        if let library {
//            print("Returning Cached Shader Library: \(configuration.label)")
            return library
        }

//        print("Creating Shader Library: \(configuration.label)")

        if let source = try ShaderLibrarySourceCache.getLibrarySource(configuration: configuration) {
            library = try device.makeLibrary(source: source, options: nil)
        }
        else if let url = configuration.libraryURL {
            library = try device.makeLibrary(URL: url)
        }
        else if let defaultLibrary = getDefaultLibrary(device: device) {
            library = defaultLibrary
        }

        if let library {
            libraryQueue.sync(flags: .barrier) {
                cache[configuration] = library
            }
            return library
        }
        else {
            return nil
        }
    }
}
