//
//  SatinClearRenderer.swift
//  Example
//
//  Created by OpenAI on 4/19/26.
//

#if os(macOS)

import Metal
import Satin

final class SatinClearRenderer: MetalViewRenderer {
    private let clearColor: MTLClearColor

    init(clearColor: MTLClearColor) {
        self.clearColor = clearColor
        super.init()
    }

    override var depthPixelFormat: MTLPixelFormat { .invalid }
    override var stencilPixelFormat: MTLPixelFormat { .invalid }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        encoder?.endEncoding()
    }
}

#endif
