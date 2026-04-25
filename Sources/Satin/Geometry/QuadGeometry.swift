//
//  QuadGeometry.swift
//  Satin
//
//  Created by Reza Ali on 3/19/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class QuadGeometry: SatinGeometry {
    public var size: Float {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    public init(size: Float = 2) {
        self.size = size
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateQuadGeometryData(size)
    }
}
