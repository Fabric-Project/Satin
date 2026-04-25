//
//  UVDiskGeometry.swift
//  Satin
//
//  Created by Reza Ali on 10/15/24.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class UVDiskGeometry: SatinGeometry {
    public var outerRadius: Float {
        didSet {
            if oldValue != outerRadius {
                _updateData = true
            }
        }
    }

    public var innerRadius: Float {
        didSet {
            if oldValue != innerRadius {
                _updateData = true
            }
        }
    }

    public init(innerRadius: Float = 0.85, outerRadius: Float = 1.0) {
        self.outerRadius = outerRadius
        self.innerRadius = innerRadius
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateUVDiskGeometryData(min(innerRadius, outerRadius), max(innerRadius, outerRadius))
    }
}
