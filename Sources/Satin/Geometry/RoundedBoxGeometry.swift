//
//  RoundedBoxGeometry.swift
//  Satin
//
//  Created by Reza Ali on 3/15/22.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class RoundedBoxGeometry: SatinGeometry {
    public var size: simd_float3 {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    public var radius: Float {
        didSet {
            if oldValue != radius {
                _updateData = true
            }
        }
    }

    public var resolution: Int {
        didSet {
            if oldValue != resolution {
                _updateData = true
            }
        }
    }

    public init(size: Float = 2, radius: Float = 0.25, resolution: Int = 1) {
        self.size = .init(repeating: size)
        self.radius = radius
        self.resolution = resolution
        super.init()
    }

    public init(size: simd_float3 = .init(repeating: 2.0), radius: Float = 0.25, resolution: Int = 1) {
        self.size = size
        self.radius = radius
        self.resolution = resolution
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateRoundedBoxGeometryData(size.x, size.y, size.z, radius, Int32(resolution))
    }
}
