//
//  TessellationGeometry.swift
//  Satin
//
//  Created by Reza Ali on 4/1/23.
//  Copyright © 2023 Reza Ali. All rights reserved.
//

import Foundation
import Metal

public final class TessellationGeometry: Geometry {
    private let baseGeometry: Geometry

    public var patchCount: Int {
        if indexCount > 0 {
            return indexCount / 3
        } else {
            return vertexCount / 3
        }
    }

    public var controlPointsPerPatch: Int {
        3
    }

    public var partitionMode: MTLTessellationPartitionMode {
        .integer
    }

    public var factorStepFunction: MTLTessellationFactorStepFunction {
        .perPatch
    }

    public var controlPointBuffer: MTLBuffer? {
        if baseGeometry is SatinGeometry {
            return vertexBuffers[VertexBufferIndex.Vertices]
        } else {
            return vertexBuffers[VertexBufferIndex.Position]
        }
    }

    public var controlPointIndexBuffer: MTLBuffer? {
        indexBuffer
    }

    public var controlPointIndexType: MTLTessellationControlPointIndexType {
        guard let indexType else { return .none }
        if indexType == .uint32 {
            return .uint32
        } else {
            return .uint16
        }
    }

    public init(baseGeometry: Geometry) {
        self.baseGeometry = baseGeometry
        super.init(primitiveType: baseGeometry.primitiveType, windingOrder: baseGeometry.windingOrder)
        for (index, attribute) in baseGeometry.vertexAttributes {
            addAttribute(attribute, for: index)
        }

        if let elementBuffer = baseGeometry.elementBuffer {
            setElements(elementBuffer)
        }
    }

    override public var vertexDescriptor: MTLVertexDescriptor {
        let descriptor = super.generateVertexDescriptor()
        descriptor.layouts[VertexBufferIndex.Vertices.rawValue].stepRate = 1
        descriptor.layouts[VertexBufferIndex.Vertices.rawValue].stepFunction = .perPatchControlPoint
        return descriptor
    }

    override public var tessellationDescriptor: TessellationDescriptor {
        TessellationDescriptor(
            partitionMode: partitionMode,
            factorStepFunction: factorStepFunction,
            outputWindingOrder: windingOrder,
            controlPointIndexType: controlPointIndexType
        )
    }

    override public func draw(renderEncoderState: RenderEncoderState, instanceCount: Int, indexBufferOffset: Int = 0, vertexStart: Int = 0) {
        let renderEncoder = renderEncoderState.renderEncoder
        if let indexBuffer {
            renderEncoder.drawIndexedPatches(
                numberOfPatchControlPoints: controlPointsPerPatch,
                patchStart: 0,
                patchCount: patchCount,
                patchIndexBuffer: nil,
                patchIndexBufferOffset: 0,
                controlPointIndexBuffer: indexBuffer,
                controlPointIndexBufferOffset: 0,
                instanceCount: instanceCount,
                baseInstance: 0
            )
        } else {
            renderEncoder.drawPatches(
                numberOfPatchControlPoints: controlPointsPerPatch,
                patchStart: 0,
                patchCount: patchCount,
                patchIndexBuffer: nil,
                patchIndexBufferOffset: 0,
                instanceCount: instanceCount,
                baseInstance: 0
            )
        }
    }
}
