//
//  BloomGenerator.swift
//  Example
//
//  Created by Reza Ali on 9/3/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Foundation
import Metal

public final class BloomGenerator {
    final class DownscaleComputeSystem: TextureComputeSystem {}
    private var downscalars = [DownscaleComputeSystem]()

    final class UpscaleComputeSystem: TextureComputeSystem {}
    private var upscalars = [UpscaleComputeSystem]()

    public let levels: Int
    private var size: simd_int2 = .zero

    public init(device: MTLDevice, levels: Int) {
        self.levels = levels
        for i in 0 ... levels {
            if i > 0 {
                downscalars.append(DownscaleComputeSystem(
                    device: device,
                    pipelinesURL: getResourceAssetsSharedPipelinesURL(),
                    textureDescriptors: [],
                    live: true
                ))
            }

            if i < levels {
                upscalars.append(UpscaleComputeSystem(
                    device: device,
                    pipelinesURL: getResourceAssetsSharedPipelinesURL(),
                    textureDescriptors: [],
                    live: true
                ))
            }
        }
    }

    public func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture) throws -> MTLTexture? {
#if DEBUG
        commandBuffer.pushDebugGroup("Bloom Generator")
        defer { commandBuffer.popDebugGroup() }
#endif

        if size.x != sourceTexture.width || size.y != sourceTexture.height {
            for l in 0 ..< levels {
                downscalars[l].textureDescriptors = [getTextureDescriptor(sourceTexture: sourceTexture, level: l + 1)]
                upscalars[l].textureDescriptors = [getTextureDescriptor(sourceTexture: sourceTexture, level: l)]
            }
            size = simd_make_int2(Int32(sourceTexture.width), Int32(sourceTexture.height))
        }

        var prevTexture: MTLTexture? = sourceTexture
        var firstDown = true
        for downscalar in downscalars {
            downscalar.set("First", firstDown)
            firstDown = false
            downscalar.set(prevTexture, index: ComputeTextureIndex.Custom1)
            try downscalar.update(commandBuffer)
            prevTexture = downscalar.dstTexture
        }

        var i = levels - 1
        var firstUp = true
        for upscalar in upscalars.reversed() {
            upscalar.set(prevTexture, index: ComputeTextureIndex.Custom1)
            upscalar.set(firstUp ? nil : downscalars[i].dstTexture, index: ComputeTextureIndex.Custom2)
            try upscalar.update(commandBuffer)
            prevTexture = upscalar.dstTexture
            i -= 1
            firstUp = false
        }

        return prevTexture
    }

    func getTextureDescriptor(sourceTexture: MTLTexture, level: Int, mipmapped: Bool = false) -> MTLTextureDescriptor {
        let scale = Int(pow(2.0, Float(level)))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: sourceTexture.pixelFormat,
            width: max(1, sourceTexture.width/scale),
            height: max(1, sourceTexture.height/scale),
            mipmapped: false
        )

        descriptor.textureType = sourceTexture.textureType
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate

        return descriptor
    }
}
