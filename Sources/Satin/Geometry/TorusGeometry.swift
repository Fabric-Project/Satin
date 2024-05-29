//
//  TorusGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/8/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class TorusGeometry: SatinGeometry {
    public var minorRadius: Float {
        didSet {
            if oldValue != minorRadius {
                _updateGeometryData = true
            }
        }
    }

    public var majorRadius: Float {
        didSet {
            if oldValue != majorRadius {
                _updateGeometryData = true
            }
        }
    }

    public var minorResolution: Int {
        didSet {
            if oldValue != minorResolution {
                _updateGeometryData = true
            }
        }
    }

    public var majorResolution: Int {
        didSet {
            if oldValue != majorResolution {
                _updateGeometryData = true
            }
        }
    }

    public init(minorRadius: Float, majorRadius: Float, minorResolution: Int = 30, majorResolution: Int = 60) {
        self.minorRadius = minorRadius
        self.majorRadius = majorRadius
        self.minorResolution = minorResolution
        self.majorResolution = majorResolution
        super.init()
    }

    public override func generateGeometryData() -> GeometryData {
        generateTorusGeometryData(minorRadius, majorRadius, Int32(minorResolution), Int32(majorResolution))
    }
}
