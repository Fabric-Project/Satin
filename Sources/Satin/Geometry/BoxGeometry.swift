//
//  BoxGeometry.swift
//  Satin
//
//  Created by Reza Ali on 8/28/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class BoxGeometry: SatinGeometry {
    public var width: Float {
        get {
            size.x
        }
        set {
            size.x = newValue
        }
    }

    public var height: Float {
        get {
            size.y
        }
        set {
            size.y = newValue
        }
    }

    public var depth: Float {
        get {
            size.z
        }
        set {
            size.z = newValue
        }
    }

    public var size = simd_float3(repeating: 2) {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    public var center = simd_float3(repeating: 0.0) {
        didSet {
            if oldValue != center {
                _updateData = true
            }
        }
    }

    public var resolution = simd_int3(repeating: 1) {
        didSet {
            if oldValue != resolution {
                _updateData = true
            }
        }
    }

    public init(size: Float = 2, resolution: Int = 1) {
        self.size = .init(repeating: size)
        self.resolution = .init(repeating: Int32(resolution))
        super.init()
    }

    public init(size: simd_float3, resolution: Int = 1) {
        self.size = size
        self.resolution = .init(repeating: Int32(resolution))
        super.init()
    }

    public init(size: simd_float3, resolution: simd_int3 = .init(repeating: 1)) {
        self.size = size
        self.resolution = resolution
        super.init()
    }

    public init(width: Float, height: Float, depth: Float, resolution: Int = 1) {
        self.size = simd_make_float3(width, height, depth)
        self.resolution = .init(repeating: Int32(resolution))
        super.init()
    }

    public init(width: Float, height: Float, depth: Float, widthResolution: Int, heightResolution: Int, depthResolution: Int) {
        self.size = simd_make_float3(width, height, depth)
        self.resolution = simd_make_int3(Int32(widthResolution), Int32(heightResolution), Int32(depthResolution))
        super.init()
    }

    public init(bounds: Bounds, res: (width: Int, height: Int, depth: Int) = (1, 1, 1)) {
        self.size = bounds.size
        self.center = bounds.center
        self.resolution = simd_make_int3(Int32(res.width), Int32(res.height), Int32(res.depth))
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateBoxGeometryData(size.x, size.y, size.z, center.x, center.y, center.z, resolution.x, resolution.y, resolution.z)
    }
}
