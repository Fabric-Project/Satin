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
    private struct PendingEnvironmentTextures {
        let generation: UInt64
        let cubemap: MTLTexture?
        let irradiance: MTLTexture?
        let reflection: MTLTexture?
        let brdf: MTLTexture?
    }

    private let pendingEnvironmentLock = UnfairLock()
    private var pendingEnvironmentTextures: PendingEnvironmentTextures?
    private var environmentGeneration: UInt64 = 0
    
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

    public func setEnvironment(texture: MTLTexture, qos: DispatchQoS.QoSClass = .userInitiated, cubemapSize: Int = 512, reflectionSize: Int = 512, irradianceSize: Int = 32) {
        environment = texture
        self.cubemapSize = cubemapSize
        self.reflectionSize = reflectionSize
        self.irradianceSize = irradianceSize

        let device = texture.device
        let generation = nextEnvironmentGeneration()
        let needsBrdf = brdfTexture == nil

        DispatchQueue.global(qos: qos).async { [weak self] in
            guard let self else { return }
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            let cubemapTexture = self.setupCubemapTexture(
                device: device,
                commandBuffer: commandBuffer,
                environmentTexture: texture,
                cubemapSize: cubemapSize
            )
            let irradianceTexture = self.setupIrradianceTexture(
                device: device,
                commandBuffer: commandBuffer,
                cubemapTexture: cubemapTexture,
                irradianceSize: irradianceSize
            )
            let reflectionTexture = self.setupReflectionTexture(
                device: device,
                commandBuffer: commandBuffer,
                cubemapTexture: cubemapTexture,
                reflectionSize: reflectionSize
            )
            let brdfTexture = needsBrdf
                ? self.setupBrdfTexture(device: device, commandBuffer: commandBuffer)
                : nil

            commandBuffer.addCompletedHandler { [weak self] commandBuffer in
                guard commandBuffer.status == .completed else { return }
                self?.stageEnvironmentTextures(
                    generation: generation,
                    cubemap: cubemapTexture,
                    irradiance: irradianceTexture,
                    reflection: reflectionTexture,
                    brdf: brdfTexture
                )
            }

            commandBuffer.commit()
        }

//        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Unable to create Metal Device") }
//        let captureManager = MTLCaptureManager.shared()
//        let captureDescriptor = MTLCaptureDescriptor()
//        captureDescriptor.captureObject = device
//        do { try captureManager.startCapture(with: captureDescriptor)
//        } catch { fatalError("error when trying to capture: \(error)") }
//
//        guard let commandQueue = device.makeCommandQueue(),
//              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
//
//
//        cubemapTexture = setupCubemapTexture(device: device, commandBuffer: commandBuffer)
//        irradianceTexture = setupIrradianceTexture(device: device, commandBuffer: commandBuffer)
//        reflectionTexture = setupReflectionTexture(device: device, commandBuffer: commandBuffer)
//
//        if brdfTexture == nil {
//            brdfTexture = setupBrdfTexture(device: device, commandBuffer: commandBuffer)
//        }
//
//        commandBuffer.commit()
//        commandBuffer.waitUntilCompleted()
//        MTLCaptureManager.shared().stopCapture()
    }

    public func setEnvironmentCubemap(texture: MTLTexture, qos: DispatchQoS.QoSClass = .userInitiated, reflectionSize: Int = 512, irradianceSize: Int = 32) {
        cubemapSize = texture.width
        self.reflectionSize = reflectionSize
        self.irradianceSize = irradianceSize

        let device = texture.device
        let generation = nextEnvironmentGeneration()
        let needsBrdf = brdfTexture == nil

        DispatchQueue.global(qos: qos).async { [weak self] in
            guard let self else { return }
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            let irradianceTexture = self.setupIrradianceTexture(
                device: device,
                commandBuffer: commandBuffer,
                cubemapTexture: texture,
                irradianceSize: irradianceSize
            )
            let reflectionTexture = self.setupReflectionTexture(
                device: device,
                commandBuffer: commandBuffer,
                cubemapTexture: texture,
                reflectionSize: reflectionSize
            )
            let brdfTexture = needsBrdf
                ? self.setupBrdfTexture(device: device, commandBuffer: commandBuffer)
                : nil

            commandBuffer.addCompletedHandler { [weak self] commandBuffer in
                guard commandBuffer.status == .completed else { return }
                self?.stageEnvironmentTextures(
                    generation: generation,
                    cubemap: texture,
                    irradiance: irradianceTexture,
                    reflection: reflectionTexture,
                    brdf: brdfTexture
                )
            }

            commandBuffer.commit()
        }
    }

    override open func prepareForRender() {
        super.prepareForRender()
        adoptPendingEnvironmentTextures()
    }

    internal func stageEnvironmentTextures(
        generation: UInt64,
        cubemap: MTLTexture?,
        irradiance: MTLTexture?,
        reflection: MTLTexture?,
        brdf: MTLTexture?
    ) {
        pendingEnvironmentLock.sync {
            guard generation == environmentGeneration else { return }
            pendingEnvironmentTextures = PendingEnvironmentTextures(
                generation: generation,
                cubemap: cubemap,
                irradiance: irradiance,
                reflection: reflection,
                brdf: brdf
            )
        }
    }

    private func nextEnvironmentGeneration() -> UInt64 {
        pendingEnvironmentLock.sync {
            environmentGeneration += 1
            pendingEnvironmentTextures = nil
            return environmentGeneration
        }
    }

    internal func setPendingEnvironmentGenerationForTesting() -> UInt64 {
        nextEnvironmentGeneration()
    }

    private func adoptPendingEnvironmentTextures() {
        let pending = pendingEnvironmentLock.sync { () -> PendingEnvironmentTextures? in
            let pending = pendingEnvironmentTextures
            pendingEnvironmentTextures = nil
            return pending
        }

        guard let pending else { return }

        cubemapTexture = pending.cubemap
        irradianceTexture = pending.irradiance
        reflectionTexture = pending.reflection
        if let brdf = pending.brdf {
            brdfTexture = brdf
        }
    }

    private func setupCubemapTexture(
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer,
        environmentTexture: MTLTexture,
        cubemapSize: Int
    ) -> MTLTexture? {
        if let texture = createCubemapTexture(
            device: device,
            pixelFormat: .rgba16Float,
            size: cubemapSize,
            mipmapped: true
        )
        {
            getCubemapGenerator(device: device)
                .encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: environmentTexture,
                    destinationTexture: texture
                )
            return texture
        }
        return nil
    }

    private func setupIrradianceTexture(
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer,
        cubemapTexture: MTLTexture?,
        irradianceSize: Int
    ) -> MTLTexture? {
        if let cubemapTexture,
           let texture = createCubemapTexture(
               device: device,
               pixelFormat: .rgba16Float,
               size: irradianceSize,
               mipmapped: false
           )
        {
            getDiffuseIBLGenerator(device: device)
                .encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: cubemapTexture,
                    destinationTexture: texture
                )
            return texture
        }
        return nil
    }

    private func setupReflectionTexture(
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer,
        cubemapTexture: MTLTexture?,
        reflectionSize: Int
    ) -> MTLTexture? {
        if let cubemapTexture,
           let texture = createCubemapTexture(
               device: device,
               pixelFormat: .rgba16Float,
               size: reflectionSize,
               mipmapped: true
           )
        {
            getSpecularIBLGenerator(device: device)
                .encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: cubemapTexture,
                    destinationTexture: texture
                )
            return texture
        }
        return nil
    }

    private func setupBrdfTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        getBrdfGenerator(device: device)
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

    private func createCubemapTexture(device: MTLDevice, pixelFormat: MTLPixelFormat, size: Int, mipmapped: Bool) -> MTLTexture? {
        let desc = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: pixelFormat,
            size: size,
            mipmapped: mipmapped
        )
        desc.usage = [.shaderWrite, .shaderRead]
        desc.allowGPUOptimizedContents = true
        desc.storageMode = .private
        desc.resourceOptions = .storageModePrivate

        return device.makeTexture(descriptor: desc)
    }
}
