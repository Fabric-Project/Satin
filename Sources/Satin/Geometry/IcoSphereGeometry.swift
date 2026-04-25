//
//  IcoSphereGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/11/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class IcoSphereGeometry: SatinGeometry {
    public var radius: Float = 1 {
        didSet {
            if oldValue != radius {
                _updateData = true
            }
        }
    }

    public var resolution: Int = 1 {
        didSet {
            if oldValue != resolution {
                _updateData = true
            }
        }
    }

    public init(radius: Float, resolution: Int) {
        self.radius = radius
        self.resolution = resolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateIcoSphereGeometryData(radius, Int32(resolution))
    }
}
