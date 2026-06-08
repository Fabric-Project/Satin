//
//  ShaderPipelineCache.swift
//
//
//  Created by Reza Ali on 6/14/23.
//

import Foundation
import Metal

public final class ShaderPipelineCache: Sendable {
    private nonisolated(unsafe) static var pipelineCache: [ShaderConfiguration: MTLRenderPipelineState] = [:]

    private nonisolated(unsafe) static var shadowPipelineCache: [ShaderConfiguration: MTLRenderPipelineState] = [:]
    private nonisolated(unsafe) static var pipelineReflectionCache: [ShaderConfiguration: MTLRenderPipelineReflection] = [:]

    private nonisolated(unsafe) static var pipelineParametersCache: [ShaderConfiguration: ParameterGroup] = [:]

    private static let pipelineCacheQueue = DispatchQueue(label: "ShaderPipelineCacheQueue", attributes: .concurrent)
    private static let shadowPipelineCacheQueue = DispatchQueue(label: "ShaderShadowPipelineCacheQueue", attributes: .concurrent)
    private static let pipelineReflectionCacheQueue = DispatchQueue(label: "ShaderPipelineReflectionCacheQueue", attributes: .concurrent)
    private static let pipelineParametersCacheQueue = DispatchQueue(label: "ShaderPipelineParametersCacheQueue", attributes: .concurrent)

    public static func invalidate(configuration: ShaderConfiguration) {
        invalidatePipeline(configuration: configuration)
        invalidateShadowPipeline(configuration: configuration)
        invalidatePipelineReflection(configuration: configuration)
        invalidatePipelineParameters(configuration: configuration)
    }

    public static func invalidatePipeline(configuration: ShaderConfiguration) {
        pipelineCacheQueue.sync(flags: .barrier) {
            _ = pipelineCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidateShadowPipeline(configuration: ShaderConfiguration) {
        shadowPipelineCacheQueue.sync(flags: .barrier) {
            _ = shadowPipelineCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidatePipelineReflection(configuration: ShaderConfiguration) {
        pipelineReflectionCacheQueue.sync(flags: .barrier) {
            _ = pipelineReflectionCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidatePipelineParameters(configuration: ShaderConfiguration) {
        pipelineParametersCacheQueue.sync(flags: .barrier) {
            _ = pipelineParametersCache.removeValue(forKey: configuration)
        }
    }

    public static func getPipeline(configuration: ShaderConfiguration) throws -> (pipeline: MTLRenderPipelineState?, reflection: MTLRenderPipelineReflection?) {
        var cachedPipeline: MTLRenderPipelineState?
        var cachedReflection: MTLRenderPipelineReflection?

        pipelineCacheQueue.sync {
            cachedPipeline = pipelineCache[configuration]
        }

        pipelineReflectionCacheQueue.sync {
            cachedReflection = pipelineReflectionCache[configuration]
        }

        if let cachedPipeline, let cachedReflection {
//            print("Returning Cached Shader Pipeline: \(configuration)")
            return (cachedPipeline, cachedReflection)
        }

//        print("Creating Shader Pipeline: \(configuration)")

        guard let context = configuration.context,
              let library = try ShaderLibraryCache.getLibrary(
                  configuration: configuration.getLibraryConfiguration(),
                  device: context.device
              )
        else { return (nil, nil) }

        guard let vertexFunction = library.makeFunction(name: configuration.vertexFunctionName),
              let fragmentFunction = library.makeFunction(name: configuration.fragmentFunctionName)
        else { return (nil, nil) }

        var descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = configuration.label

        descriptor.vertexDescriptor = configuration.rendering.vertexDescriptor
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction

        if let tessellationDescriptor = configuration.rendering.tessellationDescriptor {
            descriptor.tessellationPartitionMode = tessellationDescriptor.partitionMode
            descriptor.tessellationFactorStepFunction = tessellationDescriptor.factorStepFunction
            descriptor.tessellationOutputWindingOrder = tessellationDescriptor.outputWindingOrder
            descriptor.tessellationControlPointIndexType = tessellationDescriptor.controlPointIndexType
        }

        setupRenderPipelineDescriptorContext(context: context, descriptor: &descriptor)
        setupRenderPipelineDescriptorBlending(blending: configuration.rendering.blending, descriptor: &descriptor)
        if context.alphaOitEnabled {
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.colorAttachments[0].writeMask = []
        }

        var pipelineReflection: MTLRenderPipelineReflection?

        let pipeline = try context.device.makeRenderPipelineState(
            descriptor: descriptor,
            options: [.bindingInfo, .bufferTypeInfo],
            reflection: &pipelineReflection
        )

        pipelineCacheQueue.sync(flags: .barrier) {
            pipelineCache[configuration] = pipeline
        }

        pipelineReflectionCacheQueue.sync(flags: .barrier) {
            pipelineReflectionCache[configuration] = pipelineReflection
        }

        return (pipeline, pipelineReflection)
    }

    public static func getShadowPipeline(configuration: ShaderConfiguration) throws -> MTLRenderPipelineState? {
        var cachedShadowPipeline: MTLRenderPipelineState?

        pipelineCacheQueue.sync {
            cachedShadowPipeline = shadowPipelineCache[configuration]
        }

        if let cachedShadowPipeline {
            return cachedShadowPipeline
        }

        guard let context = configuration.context,
              let library = try ShaderLibraryCache.getLibrary(configuration: configuration.getLibraryConfiguration(), device: context.device)
        else { return nil }

        guard let vertexFunction = library.makeFunction(name: configuration.shadowFunctionName) ?? library.makeFunction(name: configuration.vertexFunctionName) else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = configuration.label + " Shadow"

        descriptor.vertexDescriptor = configuration.rendering.vertexDescriptor
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = nil

        if let tessellationDescriptor = configuration.rendering.tessellationDescriptor {
            descriptor.tessellationPartitionMode = tessellationDescriptor.partitionMode
            descriptor.tessellationFactorStepFunction = tessellationDescriptor.factorStepFunction
            descriptor.tessellationOutputWindingOrder = tessellationDescriptor.outputWindingOrder
            descriptor.tessellationControlPointIndexType = tessellationDescriptor.controlPointIndexType
        }

        descriptor.rasterSampleCount = 1
        descriptor.depthAttachmentPixelFormat = context.depthPixelFormat

        let pipeline = try context.device.makeRenderPipelineState(descriptor: descriptor)

        shadowPipelineCacheQueue.sync(flags: .barrier) {
            shadowPipelineCache[configuration] = pipeline
        }

        return pipeline
    }

    public static func getPipelineReflection(configuration: ShaderConfiguration) -> MTLRenderPipelineReflection? {
        var cachedReflection: MTLRenderPipelineReflection?

        pipelineReflectionCacheQueue.sync {
            cachedReflection = pipelineReflectionCache[configuration]
        }

        return cachedReflection
    }

    public static func getPipelineParameters(configuration: ShaderConfiguration) throws -> ParameterGroup? {
        if let parameters = pipelineParametersCache[configuration] { return parameters }

        if let pipelineURL = configuration.pipelineURL,
           let shaderSource = try ShaderSourceCache.getSource(url: pipelineURL),
           let parameters = parseParameters(source: shaderSource, key: configuration.label + "Uniforms")
        {
            parameters.label = configuration.label.titleCase + " Uniforms"

            pipelineParametersCacheQueue.sync(flags: .barrier) {
                pipelineParametersCache[configuration] = parameters
            }

            return parameters
        }
        else if let reflection = pipelineReflectionCache[configuration] {
            for binding in reflection.fragmentBindings {
                if binding.index == FragmentBufferIndex.MaterialUniforms.rawValue,
                   let bufferBinding = binding as? MTLBufferBinding,
                   let bufferStruct = bufferBinding.bufferStructType
                {
                    let parameters = parseParameters(bufferStruct: bufferStruct)
                    parameters.label = configuration.label.titleCase + " Uniforms"

                    pipelineParametersCacheQueue.sync(flags: .barrier) {
                        pipelineParametersCache[configuration] = parameters
                    }

                    return parameters
                }
            }
        }

        return nil
    }
}
