//
//  SatinGeometry.swift
//
//
//  Created by Reza Ali on 7/17/23.
//

import Foundation
import Metal
import SatinCore

open class SatinGeometry: Geometry {
    public internal(set) var geometryData: GeometryData = createGeometryData()

    public var _updateGeometryData: Bool = true

    public init() {
        super.init()
        setupGeometry()
    }

    deinit {
        freeGeometryData(&geometryData)
    }

    open func setupGeometry() {
        freeGeometryData(&geometryData)
        setFrom(geometryData: generateGeometryData())
        _updateGeometryData = false
    }

    open override func update() {
        updateGeometry()
        super.update()
    }

    open func updateGeometry() {
        if _updateGeometryData {
            setupGeometry()
        }
    }

    open func generateGeometryData() -> GeometryData {
        createGeometryData()
    }

    internal func setFrom(geometryData: GeometryData) {
        self.geometryData = geometryData

        let vertexCount = Int(geometryData.vertexCount)
        let interleavedBuffer = InterleavedBuffer(
            index: .Vertices,
            data: geometryData.vertexData,
            stride: MemoryLayout<SatinVertex>.size,
            count: vertexCount,
            source: geometryData
        )

        if geometryData.indexCount > 0, let indexData = geometryData.indexData {
            setElements(
                ElementBuffer(
                    type: .uint32,
                    data: indexData,
                    count: Int(geometryData.indexCount) * 3,
                    source: geometryData
                )
            )
        } else {
            setElements(nil)
        }

        var offset = 0
        addAttribute(Float4InterleavedBufferAttribute(parent: interleavedBuffer, offset: offset), for: .Position)
        offset += MemoryLayout<Float>.size * 4
        addAttribute(Float3InterleavedBufferAttribute(parent: interleavedBuffer, offset: offset), for: .Normal)
        offset += MemoryLayout<Float>.size * 4
        addAttribute(Float2InterleavedBufferAttribute(parent: interleavedBuffer, offset: offset), for: .Texcoord)
    }
}
