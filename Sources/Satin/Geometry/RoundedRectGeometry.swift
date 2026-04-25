//
//  RoundedRectGeometry.swift
//  Satin
//
//  Created by Reza Ali on 8/3/20.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class RoundedRectGeometry: SatinGeometry {
    public var size: simd_float2 {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    public var radius: Float = 0.5 {
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

    public var cornerResolution: Int32 { Int32(2 * angularResolution / 3) }
    public var edgeX: Int32 { Int32(Float(angularResolution) * size.x / radius) / 6 }
    public var edgeY: Int32 { Int32(Float(angularResolution) * size.y / radius) / 6 }

    public init(width: Float, height: Float, radius: Float, angularResolution: Int, radialResolution: Int) {
        self.size = simd_make_float2(width, height)
        self.radius = radius
        self.angularResolution = angularResolution
        self.radialResolution = radialResolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateRoundedRectGeometryData(size.x, size.y, radius, cornerResolution, edgeX, edgeY, Int32(radialResolution), false)
    }
}
