//
//  IBLScene.swift
//
//
//  Created by Reza Ali on 3/11/23.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

@preconcurrency import Metal
import simd

open class IBLScene:  IBLEnvironment {
    
    var cubemapGenerator: CubemapGenerator? // 0.023512959480285645
        = CubemapGenerator(device: MTLCreateSystemDefaultDevice()!)
    var diffuseIBLGenerator: DiffuseIBLGenerator? // 0.3512990474700928
        = DiffuseIBLGenerator(device: MTLCreateSystemDefaultDevice()!)
    var specularIBLGenerator: SpecularIBLGenerator? // 0.09427797794342041
        = SpecularIBLGenerator(device: MTLCreateSystemDefaultDevice()!)
    var brdfGenerator: BrdfGenerator? // 0.012279033660888672
        = BrdfGenerator(device: MTLCreateSystemDefaultDevice()!, size: 512)

    private var qos: DispatchQoS.QoSClass = .userInitiated
    private var cubemapSize: Int = 512
    private var reflectionSize: Int = 512
    private var irradianceSize: Int = 32

    /// Prepares the environment asynchronously. Completion runs on the worker or Metal callback
    /// thread, after GPU completion on success, or when preparation fails. No main dispatch is added.
    public func setEnvironment(texture: MTLTexture, qos: DispatchQoS.QoSClass = .userInitiated,
                               cubemapSize: Int = 512, reflectionSize: Int = 512, irradianceSize: Int = 32,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        environment = texture
        self.cubemapSize = cubemapSize
        self.reflectionSize = reflectionSize
        self.irradianceSize = irradianceSize

        encodeEnvironment(device: texture.device, qos: qos, completion: completion) { [self] commandBuffer in
            cubemapTexture = try setupCubemapTexture(device: texture.device, commandBuffer: commandBuffer)
            try setupEnvironmentLighting(device: texture.device, commandBuffer: commandBuffer)
        }
    }

    /// Like setEnvironment, but the source is already a cubemap.
    public func setEnvironmentCubemap(texture: MTLTexture, qos: DispatchQoS.QoSClass = .userInitiated,
                                      reflectionSize: Int = 512, irradianceSize: Int = 32,
                                      completion: @escaping (Result<Void, Error>) -> Void) {
        cubemapTexture = texture
        cubemapSize = texture.width
        self.reflectionSize = reflectionSize
        self.irradianceSize = irradianceSize

        encodeEnvironment(device: texture.device, qos: qos, completion: completion) { [self] commandBuffer in
            try setupEnvironmentLighting(device: texture.device, commandBuffer: commandBuffer)
        }
    }

    private func setupEnvironmentLighting(device: MTLDevice, commandBuffer: MTLCommandBuffer) throws {
        irradianceTexture = try setupIrradianceTexture(device: device, commandBuffer: commandBuffer)
        reflectionTexture = try setupReflectionTexture(device: device, commandBuffer: commandBuffer)
        if brdfTexture == nil {
            brdfTexture = try setupBrdfTexture(device: device, commandBuffer: commandBuffer)
        }
    }

    private func encodeEnvironment(device: MTLDevice, qos: DispatchQoS.QoSClass,
                                   completion: @escaping (Result<Void, Error>) -> Void,
                                   work: @escaping (MTLCommandBuffer) throws -> Void) {
        DispatchQueue.global(qos: qos).async {
            do {
                guard let commandQueue = device.makeCommandQueue() else { throw GPUError.commandQueueCreationFailed }
                guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw GPUError.commandBufferCreationFailed }
                try work(commandBuffer)
                commandBuffer.addCompletedHandler { completed in
                    if completed.status == .completed {
                        completion(.success(()))
                    } else {
                        completion(.failure(completed.error ?? GPUError.commandExecutionFailed))
                    }
                }
                commandBuffer.commit()
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func setupCubemapTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        if let hdriTexture = environment,
           let texture = try createCubemapTexture(
               device: device,
               pixelFormat: .rgba16Float,
               size: cubemapSize,
               mipmapped: true
           )
        {
            try getCubemapGenerator(device: device)
                .encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: hdriTexture,
                    destinationTexture: texture
                )
            return texture
        }
        return nil
    }

    private func setupIrradianceTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        if let cubemapTexture = cubemapTexture,
           let texture = try createCubemapTexture(
               device: device,
               pixelFormat: .rgba16Float,
               size: irradianceSize,
               mipmapped: false
           )
        {
            try getDiffuseIBLGenerator(device: device)
                .encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: cubemapTexture,
                    destinationTexture: texture
                )
            return texture
        }
        return nil
    }

    private func setupReflectionTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        if let cubemapTexture = cubemapTexture,
           let texture = try createCubemapTexture(
               device: device,
               pixelFormat: .rgba16Float,
               size: reflectionSize,
               mipmapped: true
           )
        {
            try getSpecularIBLGenerator(device: device)
                .encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: cubemapTexture,
                    destinationTexture: texture
                )
            return texture
        }
        return nil
    }

    private func setupBrdfTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) throws -> MTLTexture? {
        try getBrdfGenerator(device: device)
            .encode(
                commandBuffer: commandBuffer
            )
    }

    private func getCubemapGenerator(device: MTLDevice) -> CubemapGenerator {
        if let cubemapGenerator {
            return cubemapGenerator
        } else {
            cubemapGenerator = CubemapGenerator(device: device)
            return cubemapGenerator!
        }
    }

    private func getBrdfGenerator(device: MTLDevice) -> BrdfGenerator {
        if let brdfGenerator {
            return brdfGenerator
        } else {
            brdfGenerator = BrdfGenerator(device: MTLCreateSystemDefaultDevice()!, size: 512)
            return brdfGenerator!
        }
    }

    private func getSpecularIBLGenerator(device: MTLDevice) -> SpecularIBLGenerator {
        if let specularIBLGenerator {
            return specularIBLGenerator
        } else {
            specularIBLGenerator = SpecularIBLGenerator(device: device)
            return specularIBLGenerator!
        }
    }

    private func getDiffuseIBLGenerator(device: MTLDevice) -> DiffuseIBLGenerator {
        if let diffuseIBLGenerator {
            return diffuseIBLGenerator
        } else {
            diffuseIBLGenerator = DiffuseIBLGenerator(device: device)
            return diffuseIBLGenerator!
        }
    }

    private func createCubemapTexture(device: MTLDevice, pixelFormat: MTLPixelFormat, size: Int, mipmapped: Bool) throws -> MTLTexture? {
        let desc = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: pixelFormat,
            size: size,
            mipmapped: mipmapped
        )
        desc.usage = [.shaderWrite, .shaderRead]
        desc.allowGPUOptimizedContents = true
        desc.storageMode = .private
        desc.resourceOptions = .storageModePrivate

        guard let texture = device.makeTexture(descriptor: desc) else { throw GPUError.allocationFailed }
        return texture
    }
}
