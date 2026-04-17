//
//  TriangleGeometry.swift
//  Satin
//
//  Created by Reza Ali on 9/6/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class TriangleGeometry: SatinGeometry {
    public var size: Float {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    public init(context: Context, size: Float = 1) {
        self.size = size
        super.init(context: context)
    }

    override public func generateGeometryData() -> GeometryData {
        generateTriangleGeometryData(size)
    }
}
