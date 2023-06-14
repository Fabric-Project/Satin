//
//  SourceShader.swift
//  Satin
//
//  Created by Reza Ali on 12/9/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import Combine
import Metal

open class SourceShader: Shader {

    public var pipelineURL: URL? {
        didSet {
            if pipelineURL != nil, oldValue != pipelineURL {
                sourceNeedsUpdate = true
            }
        }
    }

    public internal(set) var source: String?
    public var shaderSource: String? {
        didSet {
            if shaderSource != nil, oldValue != shaderSource {
                sourceNeedsUpdate = true
            }
        }
    }

    open var sourceNeedsUpdate = true {
        didSet {
            if sourceNeedsUpdate {
                libraryNeedsUpdate = true
            }
        }
    }

    override public var instancing: Bool {
        didSet {
            if oldValue != instancing {
                sourceNeedsUpdate = true
            }
        }
    }

    override public var receiveShadow: Bool {
        didSet {
            if oldValue != receiveShadow {
                sourceNeedsUpdate = true
            }
        }
    }

    override public var lighting: Bool {
        didSet {
            if oldValue != lighting {
                sourceNeedsUpdate = true
            }
        }
    }

    override public var maxLights: Int {
        didSet {
            if oldValue != maxLights {
                sourceNeedsUpdate = true
            }
        }
    }

    override public var shadowCount: Int {
        didSet {
            if oldValue != shadowCount {
                sourceNeedsUpdate = true
            }
        }
    }

    open var constants: [String] {
        []
    }

    open var defines: [String: NSObject] {
        var results = [String: NSObject]()

        #if os(iOS)
        results["MOBILE"] = NSString(string: "true")
        #endif

        for attribute in VertexAttribute.allCases {
            switch vertexDescriptor.attributes[attribute.rawValue].format {
            case .invalid:
                continue
            default:
                results[attribute.shaderDefine] = NSString(string: "true")
            }
        }

        if instancing {
            results["INSTANCING"] = NSString(string: "true")
        }

        if lighting {
            results["LIGHTING"] = NSString(string: "true")
        }

        if maxLights > 0 {
            results["MAX_LIGHTS"] = NSNumber(value: maxLights)
        }

        if receiveShadow {
            results["HAS_SHADOWS"] = NSString(string: "true")
        }

        if shadowCount > 0 {
            results["SHADOW_COUNT"] = NSNumber(value: shadowCount)
        }

        return results
    }

    public var live = false {
        didSet {
            compiler.watch = live
        }
    }

    var compilerSubscription: AnyCancellable?
    private lazy var compiler: MetalFileCompiler = MetalFileCompiler(watch: live) {
        didSet {
            compilerSubscription = compiler.onUpdatePublisher.sink { [weak self] _ in
                guard let self = self else { return }
                self.shaderSource = nil
                self.sourceNeedsUpdate = true
            }
        }
    }

    public required init(_ label: String, _ pipelineURL: URL, _ vertexFunctionName: String? = nil, _ fragmentFunctionName: String? = nil) {
        self.pipelineURL = pipelineURL
        super.init(label, vertexFunctionName, fragmentFunctionName, nil)
    }

    public required init(label: String, source: String, vertexFunctionName: String? = nil, fragmentFunctionName: String? = nil) {
        shaderSource = source
        super.init(label, vertexFunctionName, fragmentFunctionName, nil)
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func setup() {
        setupSource()
        super.setup()
    }

    override func update() {
        updateSource()
        super.update()
    }

    func updateSource() {
        if sourceNeedsUpdate {
            setupSource()
        }
    }

    override func setupParameters() {
        if let shaderSource = shaderSource, let params = parseParameters(source: shaderSource, key: label + "Uniforms") {
            params.label = label.titleCase
            parameters = params
        }
        parametersNeedsUpdate = false
    }

    override func setupLibrary() {
        guard let context = context, let source = source else { return }
        do {
            // This slows it down...
//            let compileOptions = MTLCompileOptions()
//            compileOptions.preprocessorMacros = defines
            library = try context.device.makeLibrary(source: source, options: nil)
            error = nil
        } catch {
            self.error = error
            print("\(label) Shader: \(error.localizedDescription)")
            library = nil
            pipeline = nil
        }

        libraryNeedsUpdate = false
    }

    open func setupShaderSource() -> String? {
        var result: String?

        if let pipelineURL = pipelineURL {
            do {
                result = try ShaderSourceCache.getSource(url: pipelineURL)
                compiler = ShaderSourceCache.getCompiler(url: pipelineURL)
                compiler.watch = live
                error = nil
            } catch {
                self.error = error
                print("\(label) Shader: \(error.localizedDescription)")
            }
        } else if let shaderSource = shaderSource {
            do {
                result = try compileMetalSource(shaderSource)
                error = nil
            } catch {
                self.error = error
                print("\(label) Shader: \(error.localizedDescription)")
            }
        }
        return result
    }

    open func modifyShaderSource(source: inout String) {}

    open func setupSource() {
        guard var source = RenderIncludeSource.get(),
              let compiledShaderSource = shaderSource ?? setupShaderSource() else { return }

        injectDefines(source: &source, defines: defines) // don't inject defines, use the metal way of doing it
        injectConstants(source: &source, constants: constants)

        injectShadowData(source: &source, receiveShadow: receiveShadow, shadowCount: shadowCount)
        injectShadowBuffer(source: &source, receiveShadow: receiveShadow, shadowCount: shadowCount)
        injectShadowFunction(source: &source, receiveShadow: receiveShadow, shadowCount: shadowCount)

        injectVertex(source: &source, vertexDescriptor: vertexDescriptor)

        source += compiledShaderSource

        injectPassThroughVertex(label: label, source: &source)

        if castShadow { injectPassThroughShadowVertex(label: label, source: &source) }

        injectInstancingArgs(source: &source, instancing: instancing)

        injectShadowCoords(source: &source, receiveShadow: receiveShadow, shadowCount: shadowCount)
        injectShadowVertexArgs(source: &source, receiveShadow: receiveShadow)
        injectShadowVertexCalc(source: &source, receiveShadow: receiveShadow, shadowCount: shadowCount)

        injectShadowFragmentArgs(source: &source, receiveShadow: receiveShadow, shadowCount: shadowCount)
        injectShadowFragmentCalc(source: &source, receiveShadow: receiveShadow, shadowCount: shadowCount)

        injectLightingArgs(source: &source, lighting: lighting)

        // user hook to modify shader if needed
        modifyShaderSource(source: &source)

        shaderSource = compiledShaderSource

        self.source = source

        error = nil

        sourceNeedsUpdate = false
    }

    open override func makePipeline(_ context: Context, descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState? {
        try context.device.makeRenderPipelineState(descriptor: descriptor)
    }

    override public func clone() -> Shader {
        var clone: SourceShader!

        if let pipelineURL = pipelineURL {
            clone = type(of: self).init(label, pipelineURL, vertexFunctionName, fragmentFunctionName)
        } else if let shaderSource = shaderSource {
            clone = type(of: self).init(
                label: label,
                source: shaderSource,
                vertexFunctionName: vertexFunctionName,
                fragmentFunctionName: fragmentFunctionName
            )
        } else {
            fatalError("Source Shader improperly constructed")
        }

        clone.libraryURL = libraryURL
        clone.library = library
        clone.pipelineURL = pipelineURL
        clone.pipeline = pipeline
        clone.pipelineReflection = pipelineReflection
        clone.source = source

        clone.parameters = parameters.clone()

        clone.blending = blending
        clone.sourceRGBBlendFactor = sourceRGBBlendFactor
        clone.sourceAlphaBlendFactor = sourceAlphaBlendFactor
        clone.destinationRGBBlendFactor = destinationRGBBlendFactor
        clone.destinationAlphaBlendFactor = destinationAlphaBlendFactor
        clone.rgbBlendOperation = rgbBlendOperation
        clone.alphaBlendOperation = alphaBlendOperation

        clone.instancing = instancing
        clone.lighting = lighting
        clone.vertexDescriptor = vertexDescriptor

        clone.vertexFunctionName = vertexFunctionName
        clone.fragmentFunctionName = fragmentFunctionName

        return clone
    }
}
