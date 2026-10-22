//
//  SpecularIBLGenerator.swift
//  Satin
//
//  Created by Reza Ali on 11/8/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import Metal
import simd

public final class SpecularIBLGenerator {
    final class SpecularIBLComputeProcessor: TextureComputeProcessor {
        init(device: MTLDevice) {
            super.init(
                device: device,
                pipelinesURL: getPipelinesComputeURL()!
            )
        }

        override func getSize(texture: MTLTexture, iteration: Int) -> MTLSize {
            let level = iteration / 6
            let size = Int(Float(texture.width) / pow(2.0, Float(level)))
            return MTLSize(width: size, height: size, depth: texture.depth)
        }
    }

    private var compute: SpecularIBLComputeProcessor

    public init(device: MTLDevice) {
        compute = SpecularIBLComputeProcessor(device: device)
    }

    public func encode(computeEncoder: MTLComputeCommandEncoder, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        let iterations = _encode(
            sourceTexture: sourceTexture,
            destinationTexture: destinationTexture
        )

        compute.update(computeEncoder, iterations: iterations)
    }

    public func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        let iterations = _encode(
            sourceTexture: sourceTexture,
            destinationTexture: destinationTexture
        )

        compute.update(commandBuffer, iterations: iterations)
    }

    private func _encode(sourceTexture: MTLTexture, destinationTexture: MTLTexture) -> Int {
        let levels = destinationTexture.mipmapLevelCount
        let resolution = sourceTexture.width
        let width = destinationTexture.width

        compute.set(destinationTexture, index: ComputeTextureIndex.Custom0) // output
        compute.set(sourceTexture, index: ComputeTextureIndex.Custom1) // input

        compute.preCompute = { computeEncoder, iteration in
            let face = UInt32(iteration % 6)
            let level = UInt32(iteration / 6)
            let size = UInt32(Float(width) / pow(2.0, Float(level)))
            let resolution = UInt32(resolution)
            var faceLevelSizeResolution = simd_make_uint4(face, level, size, resolution)

            computeEncoder.setBytes(&faceLevelSizeResolution, length: MemoryLayout<simd_uint4>.size, index: ComputeBufferIndex.Custom0.rawValue)
        }

        destinationTexture.label = "Specular IBL"

        return levels * 6
    }
}
