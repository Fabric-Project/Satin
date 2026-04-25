//
//  TubeGeometry.swift
//  Satin
//
//  Created by Reza Ali on 3/15/22.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class TubeGeometry: SatinGeometry {
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

    public var startAngle: Float {
        didSet {
            if oldValue != startAngle {
                _updateData = true
            }
        }
    }

    public var endAngle: Float {
        didSet {
            if oldValue != endAngle {
                _updateData = true
            }
        }
    }

    public var angularResolution: Int {
        didSet {
            if oldValue != angularResolution {
                _updateData = true
            }
        }
    }

    public var verticalResolution: Int {
        didSet {
            if oldValue != verticalResolution {
                _updateData = true
            }
        }
    }

    public init(radius: Float, height: Float, startAngle: Float, endAngle: Float, angularResolution: Int, verticalResolution: Int) {
        self.radius = radius
        self.height = height
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.angularResolution = angularResolution
        self.verticalResolution = verticalResolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateTubeGeometryData(radius, height, startAngle, endAngle, Int32(angularResolution), Int32(verticalResolution))
    }
}
