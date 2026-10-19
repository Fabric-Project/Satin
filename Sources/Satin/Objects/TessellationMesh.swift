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
    /// While false, draws keep the factors frozen when tessellation turned off.
    public var tessellate: Bool {
        didSet {
            if oldValue, !tessellate { factorsNeedFreezing = true }
            tessellatePublisher.send(tessellate)
        }
    }

    public let tessellatePublisher = PassthroughSubject<Bool, Never>()

    /// Set when tessellation turns off (or starts off): the next encode writes the factors the
    /// draws keep using, into a buffer of their own.
    private var factorsNeedFreezing: Bool

    public init(context: Context, label: String, geometry: TessellationGeometry, material: Material?, tessellator: Tessellator, tessellate: Bool = true, visible: Bool = true, renderOrder: Int = 0, renderLayer: RenderLayer = .opaque) {
        self.tessellator = tessellator
        self.tessellate = tessellate
        factorsNeedFreezing = !tessellate
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

    /// The factors the next draws bind: while tessellating, a slice of the last encode's arena, so
    /// encoding again before those draws execute writes a new slice instead of overwriting; while
    /// not, the frozen factors.
    private(set) var encodedFactors: (buffer: MTLBuffer, offset: Int)?

    override public func encode(in context: EncodingContext) {
        if tessellate {
            let factors = context.allocate(length: tessellator.factorsLength)
            tessellator.factorsDestination = factors
            tessellator.update(context.commandBuffer, iterations: 1)
            encodedFactors = factors
        } else if factorsNeedFreezing {
            // A new buffer per freeze: draws still in flight keep reading the previous one, which
            // their command buffers hold until they complete.
            if let frozenFactors = context.commandBuffer.device.makeBuffer(length: tessellator.factorsLength, options: .storageModePrivate) {
                frozenFactors.label = "\(label) Frozen Tessellation Factors"
                tessellator.factorsDestination = (frozenFactors, 0)
                tessellator.update(context.commandBuffer, iterations: 1)
                encodedFactors = (frozenFactors, 0)
            }
            factorsNeedFreezing = false
        }
        super.encode(in: context)
    }

    // MARK: - Draw

    override public func draw(in context: RenderableDrawContext) {
        guard instanceCount > 0, let material, !geometry.vertexBuffers.isEmpty,
              context.isShadowPass || context.materialPass.includes(material)
        else { return }

        context.setVertexBuffer(context.vertexUniforms.buffer, offset: context.vertexUniforms.offset, index: .VertexUniforms)
        material.draw(in: context.materialContext(layout: nil))

        // Captured now: the draw binds the factors encoded for it, whatever is encoded later.
        if let encodedFactors {
            let factorsBuffer = encodedFactors.buffer
            let factorsOffset = encodedFactors.offset
            context.addCustomCommand { renderEncoder in
                renderEncoder.setTessellationFactorBuffer(factorsBuffer, offset: factorsOffset, instanceStride: 0)
            }
        }

        geometry.draw(in: context.geometryContext(instanceCount: instanceCount))
    }
}
