//
//  SourceShader.swift
//  Satin
//
//  Created by Reza Ali on 12/9/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Combine
import Foundation
import Metal

open class SourceShader: Shader {
    public var pipelineURL: URL {
        get { configuration.pipelineURL! }
        set { configuration.pipelineURL = newValue }
    }

    public var source: String? {
        do {
            return try ShaderLibrarySourceCache.getLibrarySource(configuration: configuration.getLibraryConfiguration())
        }
        catch {
            print("\(label) Shader Source: \(error.localizedDescription)")
        }
        return nil
    }

    public var live = false {
        didSet {
            compiler.watch = live
        }
    }

    var compilerSubscription: AnyCancellable?
    private lazy var compiler = MetalFileCompiler(watch: live) {
        didSet {
            compilerSubscription = compiler.onUpdatePublisher.sink { [weak self] _ in
                guard let self = self else { return }

                ShaderSourceCache.removeSource(url: self.pipelineURL)

                ShaderLibrarySourceCache.invalidateLibrarySource(
                    configuration: self.configuration.getLibraryConfiguration()
                )

                ShaderLibraryCache.invalidateLibrary(
                    configuration: self.configuration.getLibraryConfiguration()
                )

                ShaderPipelineCache.invalidate(configuration: self.configuration)

                // invalidate caches to recompile shader
                self.pipelines.removeAll()
                self.pipelineError = nil

                self.shadowPipelines.removeAll()
                self.shadowPipelineError = nil

                self.configurations.removeAll()

                if self.castShadow {
                    self.shadowPipelineNeedsUpdate = true
                }

                self.pipelineNeedsUpdate = true
                self.parametersNeedsUpdate = true

                print("Updating Shader: \(self.label) at: \(self.pipelineURL.path)")

                self.update()
            }
        }
    }

    public init(label: String, pipelineURL: URL, pipelineDescriptor: MTLRenderPipelineDescriptor? = nil) {
        super.init(label: label, pipelineURL: pipelineURL)
        setupShaderCompiler()
    }

    public required init(configuration: ShaderConfiguration) {
        super.init(configuration: configuration)
        setupShaderCompiler()
    }
    
    deinit {
        compilerSubscription?.cancel()
    }

    open func setupShaderCompiler() {
        compiler = ShaderSourceCache.getCompiler(url: pipelineURL)
        compiler.watch = live
    }
}
