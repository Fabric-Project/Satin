//
//  RenderDestination.swift
//  Satin
//

import Metal
import simd

/// Where a submission renders: everything pipeline variants and pass setup depend on, fixed when the
/// submission is made. The render pass descriptor given when it draws must match it.
public struct RenderDestination: Equatable {
    public var colorPixelFormats: [MTLPixelFormat]
    public var depthPixelFormat: MTLPixelFormat
    public var stencilPixelFormat: MTLPixelFormat
    public var sampleCount: Int
    public var width: Int
    public var height: Int
    /// Views drawn at once by vertex amplification; 1 otherwise.
    public var viewCount: Int

    public init(
        colorPixelFormats: [MTLPixelFormat],
        depthPixelFormat: MTLPixelFormat = .invalid,
        stencilPixelFormat: MTLPixelFormat = .invalid,
        sampleCount: Int = 1,
        width: Int,
        height: Int,
        viewCount: Int = 1
    ) {
        self.colorPixelFormats = colorPixelFormats
        self.depthPixelFormat = depthPixelFormat
        self.stencilPixelFormat = stencilPixelFormat
        self.sampleCount = sampleCount
        self.width = width
        self.height = height
        self.viewCount = viewCount
    }

    /// The destination `renderPassDescriptor`'s attachments describe.
    public init(renderPassDescriptor: MTLRenderPassDescriptor, viewCount: Int = 1) {
        var colorPixelFormats: [MTLPixelFormat] = []
        var sampleCount = 1
        var width = renderPassDescriptor.renderTargetWidth
        var height = renderPassDescriptor.renderTargetHeight

        for index in 0 ..< 8 {
            guard let texture = renderPassDescriptor.colorAttachments[index].texture else { break }
            colorPixelFormats.append(texture.pixelFormat)
            sampleCount = max(sampleCount, texture.sampleCount)
            if width == 0 { width = texture.width }
            if height == 0 { height = texture.height }
        }

        let depthTexture = renderPassDescriptor.depthAttachment.texture
        let stencilTexture = renderPassDescriptor.stencilAttachment.texture
        if let depthTexture {
            sampleCount = max(sampleCount, depthTexture.sampleCount)
            if width == 0 { width = depthTexture.width }
            if height == 0 { height = depthTexture.height }
        }

        self.init(
            colorPixelFormats: colorPixelFormats,
            depthPixelFormat: depthTexture?.pixelFormat ?? .invalid,
            stencilPixelFormat: stencilTexture?.pixelFormat ?? .invalid,
            sampleCount: sampleCount,
            width: width,
            height: height,
            viewCount: viewCount
        )
    }
}

/// An immutable snapshot of one view: a camera's matrices and position, and the viewport it draws
/// into. A submission takes its views when it is made; preparation, drawing and custom draws all see
/// the same snapshot, and nothing reads the live camera afterwards.
public struct RenderView {
    public let viewMatrix: simd_float4x4
    public let projectionMatrix: simd_float4x4
    public let viewProjectionMatrix: simd_float4x4
    /// The camera's world matrix: the inverse of `viewMatrix`.
    public let inverseViewMatrix: simd_float4x4
    public let worldPosition: simd_float3
    public let viewDirection: simd_float3
    /// x, y, width, height.
    public let viewport: simd_float4
    /// The camera's view-projection in the frame before, for motion; equal to
    /// `viewProjectionMatrix` when the view was made without a frame.
    public let previousViewProjectionMatrix: simd_float4x4

    public init(camera: Camera, viewport: simd_float4) {
        viewMatrix = camera.viewMatrix
        projectionMatrix = camera.projectionMatrix
        viewProjectionMatrix = camera.viewProjectionMatrix
        inverseViewMatrix = camera.worldMatrix
        worldPosition = camera.worldPosition
        viewDirection = camera.viewDirection
        self.viewport = viewport
        previousViewProjectionMatrix = viewProjectionMatrix
    }

    /// `camera` as it is now, with its view-projection from the frame before `frame`.
    public init(camera: Camera, viewport: simd_float4, frame: FrameTime) {
        viewMatrix = camera.viewMatrix
        projectionMatrix = camera.projectionMatrix
        viewProjectionMatrix = camera.viewProjectionMatrix
        inverseViewMatrix = camera.worldMatrix
        worldPosition = camera.worldPosition
        viewDirection = camera.viewDirection
        self.viewport = viewport
        previousViewProjectionMatrix = camera.previousViewProjectionMatrix(frame: frame)
    }
}
