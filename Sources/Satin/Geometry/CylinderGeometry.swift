//
//  CylinderGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/8/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class CylinderGeometry: SatinGeometry {
    public var radius: Float = 1.0 {
        didSet {
            if oldValue != radius {
                _updateData = true
            }
        }
    }

    public var height: Float = 2.0 {
        didSet {
            if oldValue != height {
                _updateData = true
            }
        }
    }

    public var angularResolution: Int = 60 {
        didSet {
            if oldValue != angularResolution {
                _updateData = true
            }
        }
    }

    public var radialResolution: Int = 1 {
        didSet {
            if oldValue != radialResolution {
                _updateData = true
            }
        }
    }

    public var verticalResolution: Int = 1 {
        didSet {
            if oldValue != verticalResolution {
                _updateData = true
            }
        }
    }

    public init(radius: Float, height: Float, angularResolution: Int = 60, radialResolution: Int = 1, verticalResolution: Int = 1) {
        self.radius = radius
        self.height = height
        self.angularResolution = angularResolution
        self.radialResolution = radialResolution
        self.verticalResolution = verticalResolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateCylinderGeometryData(radius, height, Int32(angularResolution), Int32(radialResolution), Int32(verticalResolution))
    }
}
