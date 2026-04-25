//
//  TessellationMesh.swift
//  Satin
//
//  Created by Reza Ali on 3/31/23.
//  Copyright © 2023 Reza Ali. All rights reserved.
//

import Combine
import Foundation
import Metal
import simd

open class TessellationMesh: Mesh {
    public var tessellator: Tessellator
    public var tessellate: Bool {
        didSet {
            tessellatePublisher.send(tessellate)
        }
    }

    public let tessellatePublisher = PassthroughSubject<Bool, Never>()

    public init(label: String, geometry: TessellationGeometry, material: Material?, tessellator: Tessellator, tessellate: Bool = true, visible: Bool = true, renderOrder: Int = 0, renderPass: Int = 0) {
        self.tessellator = tessellator
        self.tessellate = tessellate
        super.init(
            label: label,
            geometry: geometry,
            material: material,
            visible: visible,
            renderOrder: renderOrder,
            renderPass: renderPass
        )
    }

    public required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    override public func encode(_ commandBuffer: any MTLCommandBuffer) {
        if tessellate {
            tessellator.update(commandBuffer, iterations: 1)
        }
        super.encode(commandBuffer)
    }

    // MARK: - Draw

    override public func draw(renderContext: Context, renderEncoderState: RenderEncoderState, instanceCount: Int, shadow: Bool) {
        guard instanceCount > 0, let vertexUniforms = vertexUniforms[renderContext], let material, !geometry.vertexBuffers.isEmpty else { return }

        renderEncoderState.vertexVertexUniforms = vertexUniforms

        geometry.bind(
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )

        material.bind(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )

        let renderEncoder = renderEncoderState.renderEncoder

        renderEncoder.setTessellationFactorBuffer(
            tessellator.factorsBuffer,
            offset: 0,
            instanceStride: 0
        )

        geometry.draw(renderEncoderState: renderEncoderState, instanceCount: instanceCount)
    }
}
