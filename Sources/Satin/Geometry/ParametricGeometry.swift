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

    public var vertexData: [SatinVertex] = []
    public var indexData: [UInt32] = []

    var _updateGeometry = true

    public init(context: Context, rangeU: ClosedRange<Float>, rangeV: ClosedRange<Float>, resolution: simd_int2, generator: @escaping (_ u: Float, _ v: Float) -> simd_float3) {
        self.rangeU = rangeU
        self.rangeV = rangeV
        self.resolution = resolution
        self.generator = generator
        super.init(context: context)
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
                let n0 = normalize(cross(pt, pr))
                let pb = posB - pos
                let pl = posL - pos
                let n1 = normalize(cross(pb, pl))

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

public extension ParametricGeometry {
    static func mobiusStrip(
        context: Context,
        radius: Float = 1.0,
        width: Float = 0.35,
        resolution: simd_int2 = simd_int2(192, 32)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0),
            rangeV: -width ... width,
            resolution: resolution
        ) { u, v in
            let cu = cos(u)
            let su = sin(u)
            let chu = cos(u * 0.5)
            let shu = sin(u * 0.5)
            let ring = radius + v * chu
            return [ring * cu, ring * su, v * shu]
        }
    }

    static func helicoid(
        context: Context,
        radius: Float = 1.5,
        pitch: Float = 0.2,
        turns: Float = 3.0,
        resolution: simd_int2 = simd_int2(192, 64)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0 * turns),
            rangeV: -radius ... radius,
            resolution: resolution
        ) { u, v in
            [v * cos(u), v * sin(u), pitch * u]
        }
    }

    static func superellipsoid(
        context: Context,
        radius: simd_float3 = simd_float3(repeating: 1.0),
        exponentV: Float = 0.5,
        exponentU: Float = 0.5,
        resolution: simd_int2 = simd_int2(160, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: -.pi ... .pi,
            rangeV: (-Float.pi * 0.5) ... (Float.pi * 0.5),
            resolution: resolution
        ) { u, v in
            let cv = parametricSignedPower(cos(v), exponentV)
            let sv = parametricSignedPower(sin(v), exponentV)
            let cu = parametricSignedPower(cos(u), exponentU)
            let su = parametricSignedPower(sin(u), exponentU)
            return [radius.x * cv * cu, radius.y * cv * su, radius.z * sv]
        }
    }

    static func kleinBottle(
        context: Context,
        radius: Float = 2.0,
        tube: Float = 0.55,
        resolution: simd_int2 = simd_int2(192, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0),
            rangeV: 0.0 ... (.pi * 2.0),
            resolution: resolution
        ) { u, v in
            let cu = cos(u)
            let su = sin(u)
            let hu = u * 0.5
            let chu = cos(hu)
            let shu = sin(hu)
            let sv = sin(v)
            let s2v = sin(2.0 * v)
            let ring = radius + tube * (chu * sv - shu * s2v)
            let z = tube * (shu * sv + chu * s2v)
            return [ring * cu, ring * su, z]
        }
    }

    static func catenoid(
        context: Context,
        radius: Float = 0.75,
        height: Float = 2.0,
        resolution: simd_int2 = simd_int2(160, 96)
    ) -> ParametricGeometry {
        let halfHeight = height * 0.5
        return ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0),
            rangeV: -halfHeight ... halfHeight,
            resolution: resolution
        ) { u, v in
            let r = radius * cosh(v / max(radius, 0.0001))
            return [r * cos(u), r * sin(u), v]
        }
    }

    static func paraboloid(
        context: Context,
        radiusX: Float = 1.0,
        radiusY: Float = 1.0,
        height: Float = 2.0,
        resolution: simd_int2 = simd_int2(160, 80)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0),
            rangeV: 0.0 ... 1.0,
            resolution: resolution
        ) { u, v in
            [radiusX * v * cos(u), radiusY * v * sin(u), height * v * v]
        }
    }

    static func enneperSurface(
        context: Context,
        scale: Float = 0.35,
        extent: Float = 2.25,
        resolution: simd_int2 = simd_int2(160, 160)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: -extent ... extent,
            rangeV: -extent ... extent,
            resolution: resolution
        ) { u, v in
            let x = u - (u * u * u) / 3.0 + u * v * v
            let y = v - (v * v * v) / 3.0 + v * u * u
            let z = u * u - v * v
            return scale * simd_make_float3(x, y, z)
        }
    }

    static func pseudosphere(
        context: Context,
        radius: Float = 1.0,
        heightExtent: Float = 3.0,
        resolution: simd_int2 = simd_int2(192, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0),
            rangeV: -heightExtent ... heightExtent,
            resolution: resolution
        ) { u, v in
            let sv = parametricSech(v)
            let z = v - tanh(v)
            return radius * simd_make_float3(sv * cos(u), sv * sin(u), z)
        }
    }

    static func dupinCyclide(
        context: Context,
        majorRadius: Float = 1.5,
        minorRadius: Float = 0.45,
        torusOffset: Float = 2.4,
        inversionRadius: Float = 1.0,
        resolution: simd_int2 = simd_int2(192, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0),
            rangeV: 0.0 ... (.pi * 2.0),
            resolution: resolution
        ) { u, v in
            let ring = majorRadius + minorRadius * cos(v)
            let torusPoint = simd_make_float3(
                ring * cos(u) + torusOffset,
                ring * sin(u),
                minorRadius * sin(v)
            )
            let lengthSquared = max(simd_length_squared(torusPoint), 0.0001)
            return torusPoint * ((inversionRadius * inversionRadius) / lengthSquared)
        }
    }

    static func romanSurface(
        context: Context,
        scale: Float = 2.0,
        resolution: simd_int2 = simd_int2(160, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... (.pi * 2.0),
            rangeV: (-Float.pi * 0.5) ... (Float.pi * 0.5),
            resolution: resolution
        ) { u, v in
            let sx = cos(u) * cos(v)
            let sy = sin(u) * cos(v)
            let sz = sin(v)
            return scale * simd_make_float3(sy * sz, sz * sx, sx * sy)
        }
    }

    static func crossCap(
        context: Context,
        scale: Float = 2.0,
        resolution: simd_int2 = simd_int2(160, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... .pi,
            rangeV: 0.0 ... (.pi * 2.0),
            resolution: resolution
        ) { u, v in
            let x = sin(u) * sin(u) * sin(2.0 * v) * 0.5
            let y = sin(2.0 * u) * sin(v) * 0.5
            let z = sin(2.0 * u) * cos(v) * 0.5
            return scale * simd_make_float3(x, y, z)
        }
    }

    static func bourSurface(
        context: Context,
        radius: Float = 1.35,
        turns: Float = 4.0,
        scale: Float = 0.65,
        resolution: simd_int2 = simd_int2(192, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: 0.0 ... radius,
            rangeV: 0.0 ... (.pi * turns),
            resolution: resolution
        ) { r, theta in
            let x = r * cos(theta) - 0.5 * r * r * cos(2.0 * theta)
            let y = -r * sin(theta) - 0.5 * r * r * sin(2.0 * theta)
            let z = (4.0 / 3.0) * pow(max(r, 0.0), 1.5) * cos(1.5 * theta)
            return scale * simd_make_float3(x, y, z)
        }
    }

    static func breatherSurface(
        context: Context,
        parameterA: Float = 0.4,
        rangeU: ClosedRange<Float> = -14.0 ... 14.0,
        rangeV: ClosedRange<Float> = -37.4 ... 37.4,
        scale: Float = 0.2,
        resolution: simd_int2 = simd_int2(192, 160)
    ) -> ParametricGeometry {
        let a = simd_clamp(parameterA, 0.05, 0.95)
        let b = sqrt(max(1.0 - a * a, 0.0001))
        let generator: (Float, Float) -> simd_float3 = { u, v in
            let au = a * u
            let cau = cosh(au)
            let sau = sinh(au)
            let sbv = sin(b * v)
            let cbv = cos(b * v)
            let w0 = (1.0 - a * a) * cau * cau
            let w1 = a * a * sbv * sbv
            let w = max(a * (w0 + w1), 0.0001)

            let x = -u + 2.0 * (1.0 - a * a) * cau * sau / w
            let y0 = -b * cos(v) * cbv
            let y1 = -sin(v) * sbv
            let y = 2.0 * b * cau * (y0 + y1) / w
            let z0 = -b * sin(v) * cbv
            let z1 = cos(v) * sbv
            let z = 2.0 * b * cau * (z0 + z1) / w

            return scale * simd_make_float3(x, y, z)
        }

        return ParametricGeometry(
            context: context,
            rangeU: rangeU,
            rangeV: rangeV,
            resolution: resolution,
            generator: generator
        )
    }

    static func diniSurface(
        context: Context,
        radius: Float = 1.0,
        twist: Float = 0.2,
        rangeU: ClosedRange<Float> = 0.0 ... (.pi * 4.0),
        rangeV: ClosedRange<Float> = 0.08 ... 1.45,
        resolution: simd_int2 = simd_int2(192, 96)
    ) -> ParametricGeometry {
        ParametricGeometry(
            context: context,
            rangeU: rangeU,
            rangeV: rangeV,
            resolution: resolution
        ) { u, v in
            let safeV = simd_clamp(v, 0.0001, .pi - 0.0001)
            let x = radius * cos(u) * sin(safeV)
            let y = radius * sin(u) * sin(safeV)
            let z = radius * (cos(safeV) + log(tan(safeV * 0.5))) + twist * u
            return simd_make_float3(x, y, z)
        }
    }
}

@inline(__always)
private func parametricSignedPower(_ value: Float, _ exponent: Float) -> Float {
    if value == 0.0 {
        return 0.0
    }
    return (value < 0.0 ? -1.0 : 1.0) * pow(abs(value), exponent)
}

@inline(__always)
private func parametricSech(_ value: Float) -> Float {
    1.0 / cosh(value)
}
