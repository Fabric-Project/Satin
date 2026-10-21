//
//  ARDepthUpscaler.swift
//  Example
//
//  Created by Reza Ali on 5/2/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Foundation
import Metal
import MetalPerformanceShaders

class ARDepthUpscaler {
    // Based on ARKit
    let origDepthWidth = 256
    let origDepthHeight = 192

    // Based on ARKit's Default Captured Image Size
    let origColorWidth = 1920
    let origColorHeight = 1440

    private var colorConverter: YCbCrToRGBConverter
    private var guidedFilter: MPSImageGuidedFilter
    private var scaleFilter: MPSImageBilinearScale

    private var rgbColorDownscaledTexture: MTLTexture?
    private var rgbColorDownscaledLowResTexture: MTLTexture?

    private var coefficientsTexture: MTLTexture?
    private var upscaledDepthTexture: MTLTexture?

    init(
        device: MTLDevice,
        upscaledWidth: Int = 960,
        upscaledHeight: Int = 760,
        kernelDiameter: Int = 5,
        epsilon: Float = 0.004
    ) {
        colorConverter = YCbCrToRGBConverter(device: device, width: origColorWidth, height: origColorHeight)

        guidedFilter = MPSImageGuidedFilter(device: device, kernelDiameter: kernelDiameter)
        guidedFilter.epsilon = epsilon

        scaleFilter = MPSImageBilinearScale(device: device)

        rgbColorDownscaledTexture = createTexture(
            device: device,
            label: "RGB Color Downscaled Texture",
            pixelFormat: .rgba32Float,
            width: upscaledWidth,
            height: upscaledHeight
        )

        rgbColorDownscaledLowResTexture = createTexture(
            device: device,
            label: "RGB Color Downscaled Low Res Texture",
            pixelFormat: .rgba32Float,
            width: origDepthWidth,
            height: origDepthHeight
        )

        coefficientsTexture = createTexture(
            device: device,
            label: "Coefficients Texture",
            pixelFormat: .rgba32Float,
            width: origDepthWidth,
            height: origDepthHeight
        )

        upscaledDepthTexture = createTexture(
            device: device,
            label: "Upscaled Depth Texture",
            pixelFormat: .r32Float,
            width: upscaledWidth,
            height: upscaledHeight
        )
    }

    func update(
        commands: GPUCommandRecording,
        yTexture: MTLTexture,
        cbcrTexture: MTLTexture,
        depthTexture: MTLTexture
    ) -> MTLTexture? {
        guard
            let rgbColorTexture = colorConverter.encode(commands: commands, yTexture: yTexture, cbcrTexture: cbcrTexture),
            let rgbColorDownscaledTexture, let rgbColorDownscaledLowResTexture,
            let coefficientsTexture, let upscaledDepthTexture,
            let scaleFilter = scaleFilter.copy() as? MPSImageBilinearScale,
            let guidedFilter = guidedFilter.copy() as? MPSImageGuidedFilter
        else { return nil }

        // Each invocation owns copies of its kernels. No mutable upscaler is consulted later.
        commands.append(DepthUpscaleWork(
            scaleFilter: scaleFilter,
            guidedFilter: guidedFilter,
            colorTexture: rgbColorTexture,
            downscaledColorTexture: rgbColorDownscaledTexture,
            lowResolutionColorTexture: rgbColorDownscaledLowResTexture,
            depthTexture: depthTexture,
            coefficientsTexture: coefficientsTexture,
            upscaledDepthTexture: upscaledDepthTexture
        ))
        return upscaledDepthTexture
    }

    /// The upscale's MPS work: downscale the colour twice, then guided-filter the depth against it.
    private struct DepthUpscaleWork: RecordedGPUWork {
        let scaleFilter: MPSImageBilinearScale
        let guidedFilter: MPSImageGuidedFilter
        let colorTexture: MTLTexture
        let downscaledColorTexture: MTLTexture
        let lowResolutionColorTexture: MTLTexture
        let depthTexture: MTLTexture
        let coefficientsTexture: MTLTexture
        let upscaledDepthTexture: MTLTexture

        func encode(into commandBuffer: MTLCommandBuffer) {
            commandBuffer.pushDebugGroup("Depth Upscaler")
            defer { commandBuffer.popDebugGroup() }
            scaleFilter.encode(commandBuffer: commandBuffer, sourceTexture: colorTexture,
                               destinationTexture: downscaledColorTexture)
            scaleFilter.encode(commandBuffer: commandBuffer, sourceTexture: colorTexture,
                               destinationTexture: lowResolutionColorTexture)
            guidedFilter.encodeRegression(to: commandBuffer, sourceTexture: depthTexture,
                guidanceTexture: lowResolutionColorTexture, weightsTexture: nil,
                destinationCoefficientsTexture: coefficientsTexture)
            guidedFilter.encodeReconstruction(to: commandBuffer, guidanceTexture: downscaledColorTexture,
                coefficientsTexture: coefficientsTexture, destinationTexture: upscaledDepthTexture)
        }
    }

    func createTexture(
        device: MTLDevice,
        label: String,
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = usage
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }
}

#endif
