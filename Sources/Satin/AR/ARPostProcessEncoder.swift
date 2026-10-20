//
//  ARPostProcessEncoder.swift
//  Example
//
//  Created by Reza Ali on 3/16/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Foundation
import Metal

public class ARPostProcessEncoder: PostProcessEncoder {
    public var contentTexture: MTLTexture? {
        didSet {
            if let material = mesh.material as? ARPostMaterial {
                material.contentTexture = contentTexture
            }
        }
    }

    /// Seconds that drive the camera grain: set it from the frame's time each frame.
    public var time: TimeInterval = 0 {
        didSet {
            if let material = mesh.material as? ARPostMaterial {
                material.time = time
            }
        }
    }

    var session: ARSession

    public init(label: String, context: Context, session: ARSession) {
        self.session = session
        super.init(label: label, context: context, material: ARPostMaterial(context: context))
        postProcessRenderer.colorLoadAction = .load
    }

    func update(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        guard let frame = session.currentFrame else { return }
        if let material = mesh.material as? ARPostMaterial {
            material.set("Camera Grain Intensity", frame.cameraGrainIntensity)
            material.cameraGrainTexture = frame.cameraGrainTexture
        }
    }

    override public func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        update(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
        super.draw(frame: frame, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    override public func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, renderTarget: MTLTexture) {
        update(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
        super.draw(frame: frame, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, renderTarget: renderTarget)
    }
}

#endif
