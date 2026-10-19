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

    public init(context: Context, label: String, geometry: TessellationGeometry, material: Material?, tessellator: Tessellator, tessellate: Bool = true, visible: Bool = true, renderOrder: Int = 0, renderLayer: RenderLayer = .opaque) {
        self.tessellator = tessellator
        self.tessellate = tessellate
        super.init(
            context: context,
            label: label,
            geometry: geometry,
            material: material,
            visible: visible,
            renderOrder: renderOrder,
            renderLayer: renderLayer
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

    override public func draw(in context: RenderableDrawContext) {
        guard instanceCount > 0, let material, !geometry.vertexBuffers.isEmpty else { return }

        context.setVertexBuffer(context.vertexUniforms.buffer, offset: context.vertexUniforms.offset, index: .VertexUniforms)

        let geometryContext = context.geometryContext(instanceCount: instanceCount)
        geometry.recordBindings(in: geometryContext)
        material.draw(in: context.materialContext(layout: nil))

        if let factorsBuffer = tessellator.factorsBuffer {
            context.addCustomCommand { renderEncoder in
                renderEncoder.setTessellationFactorBuffer(factorsBuffer, offset: 0, instanceStride: 0)
            }
        }

        geometry.recordDrawCall(in: geometryContext)
    }
}
