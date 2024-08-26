//
//  MetalLibraryCompiler.swift
//  Satin
//
//  Created by Reza Ali on 8/6/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Foundation

public enum MetalFileCompilerError: Error {
    case invalidFile(_ fileURL: URL)
}

extension MetalFileCompilerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidFile(fileURL):
            return NSLocalizedString("MetalFileCompiler did not find: \(fileURL.path)\n\n\n", comment: "MetalFileCompiler Error")
        }
    }
}

public final class MetalFileCompiler {
    public var watch: Bool {
        didSet {
            if watch != oldValue {
                for watcher in watchers {
                    if watch {
                        watcher.watch()
                    } else {
                        watcher.unwatch()
                    }
                }
            }
        }
    }

    public let onUpdatePublisher = PassthroughSubject<Void, Never>()

    private var files: [URL] = []
    private var watchers: [FileWatcher] = []

    public init(watch: Bool = true) {
        self.watch = watch
    }

    public func touch() {
        onUpdatePublisher.send()
    }

    public func parse(_ fileURL: URL) throws -> String {
        files = []
        watchers = []
        return try _parse(fileURL)
    }

    private func _parse(_ fileURL: URL) throws -> String {
        var fileURLResolved = fileURL.resolvingSymlinksInPath()

        guard !files.contains(fileURLResolved) else { return "" }


        let baseURL = fileURL.deletingLastPathComponent()

        var content = ""

        do {
            content = try String(contentsOf: fileURLResolved, encoding: .utf8)
        } catch {
            let pathComponents = fileURLResolved.pathComponents

            if let index = pathComponents.lastIndex(of: "Satin"),
               var frameworkFileURL = getPipelinesSatinURL()
            {
                for i in (index + 1) ..< pathComponents.count {
                    frameworkFileURL.appendPathComponent(pathComponents[i])
                }

                if !files.contains(frameworkFileURL) {
                    content = try String(contentsOf: frameworkFileURL, encoding: .utf8)
                    fileURLResolved = frameworkFileURL
                }

            } else if let index = pathComponents.lastIndex(of: "Chunks"),
                      var frameworkFileURL = getPipelinesChunksURL()
            {
                for i in (index + 1) ..< pathComponents.count {
                    frameworkFileURL.appendPathComponent(pathComponents[i])
                }

                if !files.contains(frameworkFileURL) {
                    content = try String(contentsOf: frameworkFileURL, encoding: .utf8)
                    fileURLResolved = frameworkFileURL
                }

            } else if let index = pathComponents.lastIndex(of: "Library"),
                      var frameworkFileURL = getPipelinesLibraryURL()
            {
                for i in (index + 1) ..< pathComponents.count {
                    frameworkFileURL.appendPathComponent(pathComponents[i])
                }

                if !files.contains(frameworkFileURL) {
                    content = try String(contentsOf: frameworkFileURL, encoding: .utf8)
                    fileURLResolved = frameworkFileURL
                }

            } else {
                throw MetalFileCompilerError.invalidFile(fileURLResolved)
            }
        }

        watchers.append(
            FileWatcher(
                filePath: fileURLResolved.path,
                timeInterval: 0.25,
                active: watch
            ) { [weak self] in
                ShaderSourceCache.removeSource(url: fileURL)
                self?.onUpdatePublisher.send()
            }
        )

        files.append(fileURLResolved)

        let pattern = #"^#include\s+\"(.*)\"\n"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let nsrange = NSRange(content.startIndex ..< content.endIndex, in: content)
        var matches = regex.matches(in: content, options: [], range: nsrange)
        while !matches.isEmpty {
            let match = matches[0]
            if match.numberOfRanges == 2,
               let r0 = Range(match.range(at: 0), in: content),
               let r1 = Range(match.range(at: 1), in: content)
            {
                let includeURL = URL(fileURLWithPath: String(content[r1]), relativeTo: baseURL)
                do {
                    let includeContent = try _parse(includeURL)
                    content.replaceSubrange(r0, with: includeContent + "\n")
                } catch {
                    throw MetalFileCompilerError.invalidFile(includeURL)
                }
            }
            let nsrange = NSRange(content.startIndex ..< content.endIndex, in: content)
            matches = regex.matches(in: content, options: [], range: nsrange)
        }

        return content
    }

    deinit {
        for watcher in watchers {
            watcher.unwatch()
        }
        files = []
        watchers = []
    }
}
