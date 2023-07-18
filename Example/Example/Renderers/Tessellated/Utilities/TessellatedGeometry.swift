//
//  TessellatedGeometry.swift
//  Tesselation
//
//  Created by Reza Ali on 3/31/23.
//  Copyright © 2023 Reza Ali. All rights reserved.
//

import Foundation
import Metal
import Satin

class TessellatedGeometry: Geometry {
    var patchCount: Int { indexCount > 0 ? (indexCount / 3) : (vertexCount / 3) }
    let controlPointsPerPatch: Int = 3
    var partitionMode: MTLTessellationPartitionMode { .integer }
    var stepFunction: MTLTessellationFactorStepFunction { .perPatch }
    var controlPointBuffer: MTLBuffer? { vertexBuffers[VertexBufferIndex.Vertices] ?? nil }
    var controlPointIndexBuffer: MTLBuffer? { indexBuffer }
    var controlPointIndexType: MTLTessellationControlPointIndexType {
        guard let indexType = indexType else { return .none }
        if indexType == .uint32 {
            return .uint32
        }
        else {
            return .uint16
        }
    }

    public init(baseGeometry: Geometry) {
        super.init(primitiveType: baseGeometry.primitiveType, windingOrder: baseGeometry.windingOrder)
    }

    override func generateVertexDescriptor()  -> MTLVertexDescriptor {
        let descriptor = super.generateVertexDescriptor()
        descriptor.layouts[VertexBufferIndex.Vertices.rawValue].stepRate = 1
        descriptor.layouts[VertexBufferIndex.Vertices.rawValue].stepFunction = .perPatchControlPoint
        return descriptor
    }
}
