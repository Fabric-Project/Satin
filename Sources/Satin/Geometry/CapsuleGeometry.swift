//
//  CapsuleGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/11/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class CapsuleGeometry: SatinGeometry {
    public enum Axis: Int32 {
        case x = 0
        case y = 1
        case z = 2
    }

    public var radius: Float {
        didSet {
            if oldValue != radius {
                _updateData = true
            }
        }
    }

    public var height: Float {
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

    public var radialResolution: Int = 30 {
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

    public var axis: Axis = .y {
        didSet {
            if oldValue != axis {
                _updateData = true
            }
        }
    }

    public init(radius: Float, height: Float, axis: Axis = .y) {
        self.radius = radius
        self.height = height
        self.axis = axis

        super.init()
    }

    public init(radius: Float, height: Float, angularResolution: Int = 60, radialResolution: Int = 30, verticalResolution: Int = 1, axis: Axis = .y) {
        self.radius = radius
        self.height = height
        self.angularResolution = angularResolution
        self.radialResolution = radialResolution
        self.verticalResolution = verticalResolution
        self.axis = axis

        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateCapsuleGeometryData(radius, height, Int32(angularResolution), Int32(radialResolution), Int32(verticalResolution), axis.rawValue)
    }
}
