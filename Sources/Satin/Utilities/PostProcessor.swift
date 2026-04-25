//
//  PostProcessor.swift
//  Satin
//
//  Created by Reza Ali on 4/16/20.
//

import Foundation
import Metal
import simd

open class PostProcessor {
    public var label = "Post" {
        didSet {
            renderer.label = label + " Renderer"
            mesh.label = label + " Mesh"
            scene.label = label + " Scene"
        }
    }

    public let context: Context
    public let scene: Object
    public let mesh: Mesh
    public let camera = OrthographicCamera()

    public let renderer: Renderer

    public init(
        label: String = "Post Processor",
        context: Context,
        material: Material? = nil,
        sortObjects: Bool = true,
        clearColor: simd_float4 = .init(0, 0, 0, 1),
        colorLoadAction: MTLLoadAction = .clear,
        colorStoreAction: MTLStoreAction = .store,
        clearDepth: Double = 0,
        depthLoadAction: MTLLoadAction = .clear,
        depthStoreAction: MTLStoreAction = .store,
        clearStencil: UInt32 = 0,
        stencilLoadAction: MTLLoadAction = .clear,
        stencilStoreAction: MTLStoreAction = .dontCare,
        frameBufferOnly: Bool = true
    ) {
        self.label = label
        self.context = context
        renderer = Renderer(
            label: label + " Renderer",
            context: context,
            sortObjects: sortObjects,
            clearColor: clearColor,
            colorLoadAction: colorLoadAction,
            colorStoreAction: colorStoreAction,
            clearDepth: clearDepth,
            depthLoadAction: depthLoadAction,
            depthStoreAction: depthStoreAction,
            clearStencil: clearStencil,
            stencilLoadAction: stencilLoadAction,
            stencilStoreAction: stencilStoreAction,
            frameBufferOnly: frameBufferOnly
        )

        mesh = Mesh(label: label + "Mesh", geometry: QuadGeometry(), material: material)
        scene = Object(label: label + " Scene", [mesh])
    }

    open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, renderTarget: MTLTexture) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            renderTarget: renderTarget
        )
    }

    open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = [], renderTarget: MTLTexture) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            cameras: [camera, camera],
            viewports: viewports,
            viewMappings: viewMappings,
            renderTarget: renderTarget
        )
    }

    open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = []) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            cameras: [camera, camera],
            viewports: viewports,
            viewMappings: viewMappings
        )
    }

    open func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
    }
}
