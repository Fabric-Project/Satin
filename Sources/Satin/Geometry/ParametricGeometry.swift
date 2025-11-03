//
//  ParametricGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/11/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class ParametricGeometry: Geometry {
    public var rangeU: ClosedRange<Float> = 0.0 ... 1.0 {
        didSet {
            if oldValue != rangeU {
                _updateGeometry = true
            }
        }
    }

    public var rangeV: ClosedRange<Float> = 0.0 ... 1.0 {
        didSet {
            if oldValue != rangeV {
                _updateGeometry = true
            }
        }
    }

    public var generator: (Float, Float) -> simd_float3 {
        didSet {
            _updateGeometry = true
        }
    }

    public var resolution: simd_int2 {
        didSet {
            if oldValue != resolution {
                _updateGeometry = true
            }
        }
    }

    var vertexData: [SatinVertex] = []
    var indexData: [UInt32] = []

    var _updateGeometry = true

    public init(rangeU: ClosedRange<Float>, rangeV: ClosedRange<Float>, resolution: simd_int2, generator: @escaping (_ u: Float, _ v: Float) -> simd_float3) {
        self.rangeU = rangeU
        self.rangeV = rangeV
        self.resolution = resolution
        self.generator = generator
        super.init()
        setupGeometry()
    }

    override public func encode(_ commandBuffer: MTLCommandBuffer) {
        updateGeometry()
        super.encode(commandBuffer)
    }

    func setupGeometry() {
        generateGeometry()

        let interleavedBuffer = InterleavedBuffer(
            index: .Vertices,
            data: &vertexData,
            stride: MemoryLayout<SatinVertex>.size,
            count: vertexData.count,
            source: vertexData
        )

        if indexData.count > 0 {
            setElements(
                ElementBuffer(
                    type: .uint32,
                    data: &indexData,
                    count: indexData.count,
                    source: indexData
                )
            )
        } else {
            setElements(nil)
        }

        var offset = 0

        addAttribute(
            Float3InterleavedBufferAttribute(
                parent: interleavedBuffer,
                offset: offset
            ),
            for: .Position
        )

        offset += MemoryLayout<Float>.size * 4

        addAttribute(
            Float3InterleavedBufferAttribute(
                parent: interleavedBuffer,
                offset: offset
            ),
            for: .Normal
        )

        offset += MemoryLayout<Float>.size * 4

        addAttribute(
            Float2InterleavedBufferAttribute(
                parent: interleavedBuffer,
                offset: offset
            ),
            for: .Texcoord
        )

        _updateGeometry = false
    }

    func updateGeometry() {
        if _updateGeometry {
            setupGeometry()
        }
    }

    public func generateGeometry() {
        vertexData.removeAll(keepingCapacity: true)
        indexData.removeAll(keepingCapacity: true)

        let ru = resolution.x
        let rv = resolution.y

        // guard against div/0 when ru or rv is 0
        let ruf = max(1.0, Float(ru))
        let rvf = max(1.0, Float(rv))

        let ruInc = (rangeU.upperBound - rangeU.lowerBound) / ruf
        let rvInc = (rangeV.upperBound - rangeV.lowerBound) / rvf

        let uminf = Float(rangeU.lowerBound)
        let vminf = Float(rangeV.lowerBound)

        // NEW: non-indexed single-row path for line primitives
        if primitiveType == .lineStrip || primitiveType == .line || primitiveType == .point {
            // one row, ru+1 vertices along U, fixed V = lowerBound
            for u in 0 ... ru {
                let uf = Float(u)
                let uIn = uminf + uf * ruInc
                let pos = generator(uIn, vminf)
                // simple forward normal for 2D polylines; tweak if you need shading
                let normal = simd_make_float3(0, 0, 1)
                vertexData.append(
                    SatinVertex(position: pos,
                                normal: normal,
                                uv: simd_make_float2(uf / ruf, 0.0))
                )
            }
            // leave indexData empty → renderer will use a non-indexed draw call
            return
        }
        
        for v in 0 ... rv {
            let vf = Float(v)
            let vIn = vminf + vf * rvInc
            for u in 0 ... ru {
                let uf = Float(u)
                let uIn = uminf + uf * ruInc
                let pos = generator(uIn, vIn)

                let posT = generator(uIn, vIn - rvInc)
                let posB = generator(uIn, vIn + rvInc)
                let posL = generator(uIn - ruInc, vIn)
                let posR = generator(uIn + ruInc, vIn)

                let pt = posT - pos
                let pr = posR - pos
                let n0 = normalize(cross(pr, pt))
                let pb = posB - pos
                let pl = posL - pos
                let n1 = normalize(cross(pl, pb))

                var normal = simd_make_float3(0.0, 0.0, 0.0)
                var sum: Float = 0

                if !n0.x.isNaN, !n0.y.isNaN, !n0.z.isNaN {
                    normal = n0
                    sum += 1
                }

                if !n1.x.isNaN, !n1.y.isNaN, !n1.z.isNaN {
                    normal = n1
                    sum += 1
                }

                if sum > 0 {
                    normal.x = normal.x / sum
                    normal.y = normal.y / sum
                    normal.z = normal.z / sum
                }

                vertexData.append(
                    SatinVertex(
                        position: pos,
                        normal: normal,
                        uv: simd_make_float2(uf / ruf, vf / rvf)
                    )
                )

                if v != rv, u != ru {
                    let perLoop = ru + 1
                    let index = u + v * perLoop

                    let tl = index
                    let tr = tl + 1
                    let bl = index + perLoop
                    let br = bl + 1

                    indexData.append(UInt32(tl))
                    indexData.append(UInt32(tr))
                    indexData.append(UInt32(bl))
                    indexData.append(UInt32(tr))
                    indexData.append(UInt32(br))
                    indexData.append(UInt32(bl))
                }
            }
        }
    }
}
