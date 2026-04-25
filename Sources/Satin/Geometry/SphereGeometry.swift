//
//  SphereGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/1/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class SphereGeometry: SatinGeometry {
    public var radius: Float = 1.0 {
        didSet {
            if oldValue != radius {
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

    public var verticalResolution: Int = 30 {
        didSet {
            if oldValue != verticalResolution {
                _updateData = true
            }
        }
    }

    public init(radius: Float = 1.0, angularResolution: Int = 60, verticalResolution: Int = 30) {
        self.radius = radius
        self.angularResolution = angularResolution
        self.verticalResolution = verticalResolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateSphereGeometryData(radius, Int32(angularResolution), Int32(verticalResolution))
    }
}
