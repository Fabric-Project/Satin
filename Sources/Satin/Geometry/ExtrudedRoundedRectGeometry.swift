//
//  ExtrudedRoundedRectGeometry.swift
//  Satin
//
//  Created by Reza Ali on 8/6/20.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class ExtrudedRoundedRectGeometry: SatinGeometry {
    public var size: simd_float3 {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    public var radius: Float {
        didSet {
            if oldValue != radius {
                _updateData = true
            }
        }
    }

    public var angularResolution: Int = 32 {
        didSet {
            if oldValue != angularResolution {
                _updateData = true
            }
        }
    }

    public var radialResolution: Int = 32 {
        didSet {
            if oldValue != radialResolution {
                _updateData = true
            }
        }
    }

    public var depthResolution: Int = 1 {
        didSet {
            if oldValue != depthResolution {
                _updateData = true
            }
        }
    }

    var cornerResolution: Int32 {
        Int32(2 * angularResolution / 3)
    }

    var edgeXResolution: Int32 {
        Int32(Float(angularResolution) * size.x / radius) / 6
    }

    var edgeYResolution: Int32 {
        Int32(Float(angularResolution) * size.y / radius) / 6
    }

    public init(width: Float, height: Float, depth: Float, radius: Float, angularResolution: Int, radialResolution: Int, depthResolution: Int) {
        self.size = simd_make_float3(width, height, depth)
        self.radius = radius
        self.angularResolution = angularResolution
        self.radialResolution = radialResolution
        self.depthResolution = depthResolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateExtrudedRoundedRectGeometryData(size.x, size.y, size.z, radius, cornerResolution, edgeXResolution, edgeYResolution, Int32(depthResolution), Int32(radialResolution), false)
    }
}
