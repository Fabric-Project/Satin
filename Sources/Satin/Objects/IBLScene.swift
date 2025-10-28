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

    public func setEnvironment(texture: MTLTexture, qos: DispatchQoS.QoSClass = .userInitiated, cubemapSize: Int = 512, reflectionSize: Int = 512, irradianceSize: Int = 32) {
        environment = texture
        self.cubemapSize = cubemapSize
        self.reflectionSize = reflectionSize
        self.irradianceSize = irradianceSize

        let device = texture.device

        DispatchQueue.global(qos: qos).async { [unowned self] in
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            self.cubemapTexture = self.setupCubemapTexture(device: device, commandBuffer: commandBuffer)
            self.irradianceTexture = self.setupIrradianceTexture(device: device, commandBuffer: commandBuffer)
            self.reflectionTexture = self.setupReflectionTexture(device: device, commandBuffer: commandBuffer)

            if self.brdfTexture == nil {
                self.brdfTexture = self.setupBrdfTexture(device: device, commandBuffer: commandBuffer)
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
        cubemapTexture = texture
        cubemapSize = texture.width
        self.reflectionSize = reflectionSize
        self.irradianceSize = irradianceSize

        let device = texture.device

        DispatchQueue.global(qos: qos).async { [unowned self] in
            guard let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            self.irradianceTexture = self.setupIrradianceTexture(device: device, commandBuffer: commandBuffer)
            self.reflectionTexture = self.setupReflectionTexture(device: device, commandBuffer: commandBuffer)
            if self.brdfTexture == nil {
                self.brdfTexture = self.setupBrdfTexture(device: device, commandBuffer: commandBuffer)
            }

            commandBuffer.commit()
        }
    }

    private func setupCubemapTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let hdriTexture = environment,
           let texture = createCubemapTexture(
               device: device,
               pixelFormat: .rgba16Float,
               size: cubemapSize,
               mipmapped: true
           )
        {
            getCubemapGenerator(device: device)
                .encode(
                    commandBuffer: commandBuffer,
                    sourceTexture: hdriTexture,
                    destinationTexture: texture
                )
            return texture
        }
        return nil
    }

    private func setupIrradianceTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let cubemapTexture = cubemapTexture,
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

    private func setupReflectionTexture(device: MTLDevice, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let cubemapTexture = cubemapTexture,
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
