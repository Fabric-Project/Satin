//
//  ARDepthMaskGenerator.swift
//  Example
//
//  Created by Reza Ali on 5/15/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Foundation
import Metal

public class ARDepthMaskGenerator {
    final class ARDepthMaskComputeSystem: TextureComputeSystem {
        var realDepthTexture: MTLTexture?
        var virtualDepthTexture: MTLTexture?

        init(device: MTLDevice, textureDescriptor: MTLTextureDescriptor) {
            super.init(
                device: device,
                pipelinesURL: getPipelinesComputeURL()!,
                textureDescriptors: [textureDescriptor]
            )
        }

        override func bind(computeEncoder: MTLComputeCommandEncoder, iteration: Int) -> Int {
            var index = super.bind(computeEncoder: computeEncoder, iteration: iteration)
            computeEncoder.setTexture(realDepthTexture, index: index)
            index += 1
            computeEncoder.setTexture(virtualDepthTexture, index: index)
            index += 1
            return index
        }
    }

    private var compute: ARDepthMaskComputeSystem
    private var pixelFormat: MTLPixelFormat

    public init(device: MTLDevice, width: Int, height: Int, pixelFormat: MTLPixelFormat = .r16Float) {
        self.pixelFormat = pixelFormat
        let textureDescriptor: MTLTextureDescriptor = .texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        compute = ARDepthMaskComputeSystem(device: device, textureDescriptor: textureDescriptor)
    }

    public func encode(commandBuffer: MTLCommandBuffer, realDepthTexture: MTLTexture, virtualDepthTexture: MTLTexture) -> MTLTexture? {
        commandBuffer.label = "\(compute.label) Compute Command Buffer"
        compute.realDepthTexture = realDepthTexture
        compute.virtualDepthTexture = virtualDepthTexture
        compute.update(commandBuffer)
        let texture = compute.dstTexture
        texture?.label = "\(compute.label) Texture"
        return texture
    }

    public func resize(_ size: (width: Float, height: Float)) {
        let textureDescriptor: MTLTextureDescriptor = .texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )

        compute.textureDescriptors = [textureDescriptor]
    }
}

#endif
