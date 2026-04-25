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
            if live {
                setupShaderCompiler()
            }
            compiler?.watch = live
        }
    }

    var compilerSubscription: AnyCancellable?
    private var compiler: MetalFileCompiler? {
        didSet {
            compilerSubscription?.cancel()
            compilerSubscription = nil

            compilerSubscription = compiler?.onUpdatePublisher.sink { [weak self] _ in
                self?.reloadFromSource()
            }
        }
    }

    public convenience init(context: Context, label: String, pipelineURL: URL, pipelineDescriptor: MTLRenderPipelineDescriptor? = nil) {
        var configuration = ShaderConfiguration(
            label: label,
            vertexFunctionName: label.camelCase + "Vertex",
            fragmentFunctionName: label.camelCase + "Fragment",
            shadowFunctionName: label.camelCase + "ShadowVertex",
            pipelineURL: pipelineURL
        )
        configuration.context = context
        self.init(configuration: configuration)
    }

    public required init(configuration: ShaderConfiguration) {
        super.init(configuration: configuration)
        setupShaderCompiler()
    }

    public convenience init(context: Context, configuration: ShaderConfiguration) {
        var configuration = configuration
        configuration.context = context
        self.init(configuration: configuration)
    }
    
    deinit {
        compilerSubscription?.cancel()
        compilerSubscription = nil
        compiler = nil
    }

    open func setupShaderCompiler() {
        guard compiler == nil, live else { return }
        compiler = MetalFileCompiler(watch: live)
    }

    public func reloadFromSource() {
        ShaderSourceCache.removeSource(url: self.pipelineURL)

        ShaderLibrarySourceCache.invalidateLibrarySource(
            configuration: self.configuration.getLibraryConfiguration()
        )

        ShaderLibraryCache.invalidateLibrary(
            configuration: self.configuration.getLibraryConfiguration()
        )

        ShaderPipelineCache.invalidate(configuration: self.configuration)

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
