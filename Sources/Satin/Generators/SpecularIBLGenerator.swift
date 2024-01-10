//
//  SpecularIBLGenerator.swift
//  Satin
//
//  Created by Reza Ali on 11/8/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import Metal

public final class SpecularIBLGenerator {
    class SpecularIBLComputeSystem: TextureComputeSystem {
        var roughness: Float = 0.0
        var face: UInt32 = 0
        var sourceTexture: MTLTexture?

        init(device: MTLDevice) {
            super.init(
                device: device,
                pipelinesURL: getPipelinesComputeURL()!,
                textureDescriptors: []
            )
        }

        override func bind(_ computeEncoder: MTLComputeCommandEncoder) -> Int {
            let index = super.bind(computeEncoder)
            computeEncoder.setTexture(sourceTexture, index: index)
            return index + 1
        }

        override func bindUniforms(_ computeEncoder: MTLComputeCommandEncoder) {
            super.bindUniforms(computeEncoder)
            computeEncoder.setBytes(&face, length: MemoryLayout<UInt32>.size, index: ComputeBufferIndex.Custom0.rawValue)
            computeEncoder.setBytes(&roughness, length: MemoryLayout<Float>.size, index: ComputeBufferIndex.Custom1.rawValue)
        }
    }

    private var compute: SpecularIBLComputeSystem

    public init(device: MTLDevice) {
        compute = SpecularIBLComputeSystem(device: device)
    }

    public func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        let levels = destinationTexture.mipmapLevelCount
        var size = destinationTexture.width

        for level in 0 ..< levels {
            compute.roughness = Float(level) / Float(levels - 1)
            for face in 0 ..< 6 {
                compute.face = UInt32(face)
                compute.sourceTexture = sourceTexture
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: destinationTexture.pixelFormat, width: size, height: size, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                desc.storageMode = .private
                desc.allowGPUOptimizedContents = true
                compute.textureDescriptors = [desc]

                commandBuffer.label = "\(compute.label) Compute Command Buffer"
                compute.update(commandBuffer)

                commandBuffer.label = "\(compute.label) Blit Command Buffer"
                if let blitEncoder = commandBuffer.makeBlitCommandEncoder(), let fromTexture = compute.dstTexture {
                    blitEncoder.copy(
                        from: fromTexture,
                        sourceSlice: 0,
                        sourceLevel: 0,
                        to: destinationTexture,
                        destinationSlice: face,
                        destinationLevel: level,
                        sliceCount: 1,
                        levelCount: 1
                    )
                    blitEncoder.endEncoding()
                }
            }

            size /= 2
        }

        destinationTexture.label = "Specular IBL"
    }
}
