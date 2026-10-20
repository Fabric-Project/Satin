//
//  PostProcessEncoder.swift
//  Satin
//
//  Created by Reza Ali on 4/16/20.
//

import Foundation
import Metal
import simd

/// Draws one full-screen quad with its material: a post-processing pass. Its pass's load and store
/// settings live on `postProcessRenderer`.
open class PostProcessEncoder {
    public var label = "Post" {
        didSet {
            postProcessRenderer.label = label + " PostProcessRenderEncoder"
            mesh.label = label + " Mesh"
            scene.label = label + " Scene"
        }
    }

    public let context: Context
    public let scene: Object
    public let mesh: Mesh
    public let camera: OrthographicCamera

    public let postProcessRenderer: PostProcessRenderEncoder

    public init(
        label: String = "Post Processor",
        context: Context,
        material: Material? = nil,
        colorPixelFormat: MTLPixelFormat? = nil,
        depthPixelFormat: MTLPixelFormat? = nil,
        stencilPixelFormat: MTLPixelFormat? = nil,
        clearColor: simd_float4 = .init(0, 0, 0, 1),
        colorLoadAction: MTLLoadAction = .clear,
        colorStoreAction: MTLStoreAction = .store,
        frameBufferOnly: Bool = true
    ) {
        self.label = label
        self.context = context
        camera = OrthographicCamera(context: context)
        postProcessRenderer = PostProcessRenderEncoder(
            label: label + " PostProcessRenderEncoder",
            context: context,
            colorPixelFormat: colorPixelFormat ?? context.colorPixelFormat,
            depthPixelFormat: depthPixelFormat ?? context.depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat ?? context.stencilPixelFormat,
            clearColor: clearColor,
            colorLoadAction: colorLoadAction,
            colorStoreAction: colorStoreAction,
            frameBufferOnly: frameBufferOnly
        )

        if let material {
            precondition(
                material.context == context,
                "PostProcessEncoder material context (\(material.context.id)) must match processor context (\(context.id))"
            )
        }

        mesh = Mesh(context: context, label: label + "Mesh", geometry: QuadGeometry(context: context), material: material)
        scene = Object(context: context, label: label + " Scene", [mesh])
    }

    open func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, renderTarget: MTLTexture) {
        postProcessRenderer.draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            camera: camera,
            renderTarget: renderTarget
        )
    }

    open func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        postProcessRenderer.draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            camera: camera
        )
    }

    open func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = [], renderTarget: MTLTexture) {
        postProcessRenderer.draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            cameras: [camera, camera],
            viewports: viewports,
            viewMappings: viewMappings,
            renderTarget: renderTarget
        )
    }

    open func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = []) {
        postProcessRenderer.draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            cameras: [camera, camera],
            viewports: viewports,
            viewMappings: viewMappings
        )
    }

    open func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        postProcessRenderer.resize(size)
    }
}
