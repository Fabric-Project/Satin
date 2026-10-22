//
//  BrdfGenerator.swift
//  Satin
//
//  Created by Reza Ali on 11/8/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import Metal

public final class BrdfGenerator {
    final class BrdfComputeProcessor: TextureComputeProcessor {
        init(device: MTLDevice) {
            super.init(device: device, pipelinesURL: getPipelinesComputeURL()!)
        }
    }

    private var compute: BrdfComputeProcessor

    public init(device: MTLDevice, size: Int) {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .rg16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        descriptor.allowGPUOptimizedContents = true

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "BRDF LUT"

        compute = BrdfComputeProcessor(device: device)
        compute.set(texture, index: ComputeTextureIndex.Custom0)
    }

    public func encode(commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        compute.update(commandBuffer)
        return compute.computeTextures[.Custom0]
    }

    public func encode(computeEncoder: MTLComputeCommandEncoder) -> MTLTexture? {
        compute.update(computeEncoder)
        return compute.computeTextures[.Custom0]
    }
}
