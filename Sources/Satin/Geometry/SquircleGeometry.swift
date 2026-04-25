//
//  SquircleGeometry.swift
//  Satin
//
//  Created by Reza Ali on 8/3/20.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class SquircleGeometry: SatinGeometry {
    public var size: Float = 2.0 {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    public var radius: Float = 4.0 {
        didSet {
            if oldValue != radius {
                _updateData = true
            }
        }
    }

    public var angularResolution: Int = 90 {
        didSet {
            if oldValue != angularResolution {
                _updateData = true
            }
        }
    }

    public var radialResolution: Int = 20 {
        didSet {
            if oldValue != radialResolution {
                _updateData = true
            }
        }
    }

    public init(size: Float, radius: Float, angularResolution: Int, radialResolution: Int) {
        self.size = size
        self.radius = radius
        self.angularResolution = angularResolution
        self.radialResolution = radialResolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateSquircleGeometryData(size, radius, Int32(angularResolution), Int32(radialResolution))
    }
}
