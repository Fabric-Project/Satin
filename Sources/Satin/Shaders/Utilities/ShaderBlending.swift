//
//  ShaderBlending.swift
//
//
//  Created by Reza Ali on 6/14/23.
//

import Foundation
import Metal

public struct ShaderBlending: Hashable {
    public var type: Blending = .disabled
    public var sourceRGBBlendFactor: MTLBlendFactor = .sourceAlpha
    public var sourceAlphaBlendFactor: MTLBlendFactor = .sourceAlpha
    public var destinationRGBBlendFactor: MTLBlendFactor = .oneMinusSourceAlpha
    public var destinationAlphaBlendFactor: MTLBlendFactor = .oneMinusSourceAlpha
    public var rgbBlendOperation: MTLBlendOperation = .add
    public var alphaBlendOperation: MTLBlendOperation = .add
}

extension ShaderBlending: Equatable {
    public static func == (lhs: ShaderBlending, rhs: ShaderBlending) -> Bool {
        if lhs.type == .custom && rhs.type == .custom {
            return lhs.sourceRGBBlendFactor == rhs.sourceRGBBlendFactor &&
                lhs.sourceAlphaBlendFactor == rhs.sourceAlphaBlendFactor &&
                lhs.destinationRGBBlendFactor == rhs.destinationRGBBlendFactor &&
                lhs.destinationAlphaBlendFactor == rhs.destinationAlphaBlendFactor &&
                lhs.rgbBlendOperation == rhs.rgbBlendOperation &&
                lhs.alphaBlendOperation == rhs.alphaBlendOperation
        }
        else {
            return lhs.type == rhs.type
        }
    }
}

extension ShaderBlending: CustomStringConvertible {
    public var description: String {
        var output = "Blending: \(type)\n"
        if type == .custom {
            output += "\t sourceRGBBlendFactor: \(sourceRGBBlendFactor) \n"
            output += "\t sourceAlphaBlendFactor: \(sourceAlphaBlendFactor) \n"
            output += "\t destinationRGBBlendFactor: \(destinationRGBBlendFactor) \n"
            output += "\t destinationAlphaBlendFactor: \(destinationAlphaBlendFactor) \n"
            output += "\t rgbBlendOperation: \(rgbBlendOperation) \n"
            output += "\t alphaBlendOperation: \(alphaBlendOperation) \n"
        }
        return output
    }
}

public func setupRenderPipelineDescriptorContext(context: Context, descriptor: inout MTLRenderPipelineDescriptor) {
    descriptor.rasterSampleCount = context.sampleCount
    descriptor.colorAttachments[0].pixelFormat = context.colorPixelFormat
    descriptor.depthAttachmentPixelFormat = context.depthPixelFormat
    descriptor.stencilAttachmentPixelFormat = context.stencilPixelFormat

    let vertexAmplificationCount = context.vertexAmplificationCount

    if vertexAmplificationCount > 1, context.device.supportsVertexAmplificationCount(vertexAmplificationCount) {
        descriptor.maxVertexAmplificationCount = vertexAmplificationCount
    }
}

public func setupRenderPipelineDescriptorBlending(blending: ShaderBlending, descriptor: inout MTLRenderPipelineDescriptor) {
    guard blending.type != .disabled, let colorAttachment = descriptor.colorAttachments[0] else { return }

    colorAttachment.isBlendingEnabled = true

    switch blending.type {
        case .alpha:
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            colorAttachment.rgbBlendOperation = .add
            colorAttachment.alphaBlendOperation = .add
        case .additive:
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .one
            colorAttachment.destinationAlphaBlendFactor = .one
            colorAttachment.rgbBlendOperation = .add
            colorAttachment.alphaBlendOperation = .add
        case .subtract:
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .oneMinusBlendColor
            colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            colorAttachment.rgbBlendOperation = .reverseSubtract
            colorAttachment.alphaBlendOperation = .add
        case .custom:
            colorAttachment.sourceRGBBlendFactor = blending.sourceRGBBlendFactor
            colorAttachment.sourceAlphaBlendFactor = blending.sourceAlphaBlendFactor
            colorAttachment.destinationRGBBlendFactor = blending.destinationRGBBlendFactor
            colorAttachment.destinationAlphaBlendFactor = blending.destinationAlphaBlendFactor
            colorAttachment.rgbBlendOperation = blending.rgbBlendOperation
            colorAttachment.alphaBlendOperation = blending.alphaBlendOperation
        case .disabled:
            colorAttachment.isBlendingEnabled = false
            break
    }
}
