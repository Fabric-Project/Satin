//
//  ComputeShaderPipelineCache.swift
//
//
//  Created by Reza Ali on 1/8/24.
//

import Foundation
import Metal

public final class ComputeShaderPipelineCache: Sendable {
    private nonisolated(unsafe) static var resetPipelineCache: [ComputeShaderConfiguration: MTLComputePipelineState] = [:]
    private nonisolated(unsafe) static var resetPipelineReflectionCache: [ComputeShaderConfiguration: MTLComputePipelineReflection] = [:]

    private nonisolated(unsafe) static var updatePipelineCache: [ComputeShaderConfiguration: MTLComputePipelineState] = [:]
    private nonisolated(unsafe) static var updatePipelineReflectionCache: [ComputeShaderConfiguration: MTLComputePipelineReflection] = [:]

    private nonisolated(unsafe) static var pipelineParametersCache: [ComputeShaderConfiguration: ParameterGroup] = [:]
    private nonisolated(unsafe) static var pipelineBuffersCache: [ComputeShaderConfiguration: [ParameterGroup]] = [:]

    private static let resetPipelineCacheQueue = DispatchQueue(label: "ComputeShaderResetPipelineCacheQueue", attributes: .concurrent)
    private static let resetPipelineReflectionCacheQueue = DispatchQueue(label: "ComputeShaderResetReflectionCacheQueue", attributes: .concurrent)

    private static let updatePipelineCacheQueue = DispatchQueue(label: "ComputeShaderUpdatePipelineCacheQueue", attributes: .concurrent)
    private static let updatePipelineReflectionCacheQueue = DispatchQueue(label: "ComputeShaderUpdateReflectionCacheQueue", attributes: .concurrent)

    private static let pipelineParametersCacheQueue = DispatchQueue(label: "ComputeShaderPipelineParametersCacheQueue", attributes: .concurrent)
    private static let pipelineBuffersCacheQueue = DispatchQueue(label: "ComputeShaderPipelineBuffersCacheQueue", attributes: .concurrent)

    public static func invalidate(configuration: ComputeShaderConfiguration) {
        invalidateResetPipeline(configuration: configuration)
        invalidateResetPipelineReflection(configuration: configuration)

        invalidateUpdatePipeline(configuration: configuration)
        invalidateUpdatePipelineReflection(configuration: configuration)

        invalidatePipelineParameters(configuration: configuration)
        invalidatePipelineBuffers(configuration: configuration)
    }

    public static func invalidateResetPipeline(configuration: ComputeShaderConfiguration) {
        resetPipelineCacheQueue.sync(flags: .barrier) {
            _ = resetPipelineCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidateResetPipelineReflection(configuration: ComputeShaderConfiguration) {
        resetPipelineReflectionCacheQueue.sync(flags: .barrier) {
            _ = resetPipelineReflectionCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidateUpdatePipeline(configuration: ComputeShaderConfiguration) {
        updatePipelineCacheQueue.sync(flags: .barrier) {
            _ = updatePipelineCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidateUpdatePipelineReflection(configuration: ComputeShaderConfiguration) {
        updatePipelineReflectionCacheQueue.sync(flags: .barrier) {
            _ = updatePipelineReflectionCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidatePipelineParameters(configuration: ComputeShaderConfiguration) {
        pipelineParametersCacheQueue.sync(flags: .barrier) {
            _ = pipelineParametersCache.removeValue(forKey: configuration)
        }
    }

    public static func invalidatePipelineBuffers(configuration: ComputeShaderConfiguration) {
        pipelineBuffersCacheQueue.sync(flags: .barrier) {
            _ = pipelineBuffersCache.removeValue(forKey: configuration)
        }
    }

    public static func getResetPipeline(configuration: ComputeShaderConfiguration) throws -> (MTLComputePipelineState?, MTLComputePipelineReflection?) {
        try getResetPipeline(
            functionName: configuration.resetFunctionName,
            configuration: configuration
        )
    }

    public static func getUpdatePipeline(configuration: ComputeShaderConfiguration) throws -> (MTLComputePipelineState?, MTLComputePipelineReflection?) {
        try getUpdatePipeline(
            functionName: configuration.updateFunctionName,
            configuration: configuration
        )
    }

    public static func getResetPipelineReflection(configuration: ComputeShaderConfiguration) -> MTLComputePipelineReflection? {
        var reflection: MTLComputePipelineReflection?

        resetPipelineReflectionCacheQueue.sync {
            reflection = resetPipelineReflectionCache[configuration]
        }

        return reflection
    }

    public static func getUpdatePipelineReflection(configuration: ComputeShaderConfiguration) -> MTLComputePipelineReflection? {
        var reflection: MTLComputePipelineReflection?

        updatePipelineReflectionCacheQueue.sync {
            reflection = updatePipelineReflectionCache[configuration]
        }

        return reflection
    }

    public static func getPipelineParameters(configuration: ComputeShaderConfiguration) throws -> ParameterGroup? {
        var parameters: ParameterGroup?

        pipelineParametersCacheQueue.sync {
            parameters = pipelineParametersCache[configuration]
        }

        if let parameters {
            return parameters
        }

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
        else if let reflection = getUpdatePipelineReflection(configuration: configuration) {
            for binding in reflection.bindings {
                if binding.index == ComputeBufferIndex.Uniforms.rawValue,
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

    public static func getPipelineBuffers(configuration: ComputeShaderConfiguration) throws -> [ParameterGroup]? {
        var parameters: [ParameterGroup]?

        pipelineBuffersCacheQueue.sync {
            parameters = pipelineBuffersCache[configuration]
        }

        if let parameters {
            return parameters
        }

        if let pipelineURL = configuration.pipelineURL,
           let shaderSource = try ShaderSourceCache.getSource(url: pipelineURL),
           let buffer = parseStruct(source: shaderSource, key: configuration.label)
        {
            buffer.label = configuration.label.titleCase

            pipelineBuffersCacheQueue.sync(flags: .barrier) {
                pipelineBuffersCache[configuration] = [buffer]
            }

            return [buffer]
        }
        else if let reflection = getUpdatePipelineReflection(configuration: configuration) {
            var parameters = [ParameterGroup]()

            for binding in reflection.bindings {
                if binding.index != ComputeBufferIndex.Uniforms.rawValue,
                   let bufferBinding = binding as? MTLBufferBinding,
                   let bufferStruct = bufferBinding.bufferStructType
                {
                    let p = parseParameters(bufferStruct: bufferStruct)
                    p.label = "\(binding.name)"
                    parameters.append(p)
                }
            }

            pipelineBuffersCacheQueue.sync(flags: .barrier) {
                pipelineBuffersCache[configuration] = parameters
            }

            return parameters
        }

        return nil
    }

    private static func getUpdatePipeline(
        functionName: String,
        configuration: ComputeShaderConfiguration
    ) throws -> (MTLComputePipelineState?, MTLComputePipelineReflection?) {
        var cachedPipeline: MTLComputePipelineState?
        var cachedReflection: MTLComputePipelineReflection?

        updatePipelineCacheQueue.sync {
            cachedPipeline = updatePipelineCache[configuration]
        }

        updatePipelineReflectionCacheQueue.sync {
            cachedReflection = updatePipelineReflectionCache[configuration]
        }

        if let cachedPipeline, let cachedReflection {
            return (cachedPipeline, cachedReflection)
        }

//        print("Creating Compute Shader Pipeline: \(configuration.label): \(functionName)")

        guard let device = configuration.device,
              let library = try ComputeShaderLibraryCache.getLibrary(
                  configuration: configuration.getLibraryConfiguration(),
                  device: device
              )
        else { return (nil, nil) }

        guard let computeFunction = library.makeFunction(name: functionName) else { return (nil, nil) }

        let descriptor = MTLComputePipelineDescriptor()
        descriptor.label = "\(configuration.label) \(functionName)"
        descriptor.computeFunction = computeFunction
        descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = configuration.compute.threadGroupSizeIsMultipleOfThreadExecutionWidth

        if configuration.libraryURL != nil {
            let (pipeline, reflection) = try device.makeComputePipelineState(
                descriptor: descriptor,
                options: [.bindingInfo, .bufferTypeInfo]
            )

            updatePipelineCacheQueue.sync(flags: .barrier) {
                updatePipelineCache[configuration] = pipeline
            }

            updatePipelineReflectionCacheQueue.sync(flags: .barrier) {
                updatePipelineReflectionCache[configuration] = reflection
            }

            return (pipeline, reflection)
        }
        else {
            let (pipeline, reflection) = try device.makeComputePipelineState(
                descriptor: descriptor,
                options: [.bindingInfo, .bufferTypeInfo]
            )

            updatePipelineCacheQueue.sync(flags: .barrier) {
                updatePipelineCache[configuration] = pipeline
            }

            updatePipelineReflectionCacheQueue.sync(flags: .barrier) {
                updatePipelineReflectionCache[configuration] = reflection
            }

            return (pipeline, reflection)
        }
    }

    private static func getResetPipeline(
        functionName: String,
        configuration: ComputeShaderConfiguration
    ) throws -> (MTLComputePipelineState?, MTLComputePipelineReflection?) {
        var cachedPipeline: MTLComputePipelineState?
        var cachedReflection: MTLComputePipelineReflection?

        resetPipelineCacheQueue.sync {
            cachedPipeline = resetPipelineCache[configuration]
        }

        resetPipelineReflectionCacheQueue.sync {
            cachedReflection = resetPipelineReflectionCache[configuration]
        }

        if let cachedPipeline, let cachedReflection {
            return (cachedPipeline, cachedReflection)
        }

        //        print("Creating Compute Shader Pipeline: \(configuration.label): \(functionName)")

        guard let device = configuration.device,
              let library = try ComputeShaderLibraryCache.getLibrary(
                  configuration: configuration.getLibraryConfiguration(),
                  device: device
              )
        else { return (nil, nil) }

        guard let computeFunction = library.makeFunction(name: functionName) else { return (nil, nil) }

        let descriptor = MTLComputePipelineDescriptor()
        descriptor.label = "\(configuration.label) \(functionName)"
        descriptor.computeFunction = computeFunction
        descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = configuration.compute.threadGroupSizeIsMultipleOfThreadExecutionWidth

        if configuration.libraryURL != nil {
            let (pipeline, reflection) = try device.makeComputePipelineState(
                descriptor: descriptor,
                options: [.bindingInfo, .bufferTypeInfo]
            )

            resetPipelineCacheQueue.sync(flags: .barrier) {
                resetPipelineCache[configuration] = pipeline
            }

            resetPipelineReflectionCacheQueue.sync(flags: .barrier) {
                resetPipelineReflectionCache[configuration] = reflection
            }

            return (pipeline, reflection)
        }
        else {
            let (pipeline, reflection) = try device.makeComputePipelineState(
                descriptor: descriptor,
                options: [.bindingInfo, .bufferTypeInfo]
            )

            resetPipelineCacheQueue.sync(flags: .barrier) {
                resetPipelineCache[configuration] = pipeline
            }

            resetPipelineReflectionCacheQueue.sync(flags: .barrier) {
                resetPipelineReflectionCache[configuration] = reflection
            }

            return (pipeline, reflection)
        }
    }
}
