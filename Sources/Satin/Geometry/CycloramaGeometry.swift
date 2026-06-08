//
//  CycloramaGeometry.swift
//  Satin
//
//  Created by OpenAI Codex on 6/2/26.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class CycloramaGeometry: SatinGeometry {
    public var width: Float {
        didSet {
            if oldValue != width {
                _updateData = true
            }
        }
    }

    public var length: Float {
        didSet {
            if oldValue != length {
                _updateData = true
            }
        }
    }

    public var depth: Float {
        didSet {
            if oldValue != depth {
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

    public var widthResolution: Int {
        didSet {
            if oldValue != widthResolution {
                _updateData = true
            }
        }
    }

    public var lengthResolution: Int {
        didSet {
            if oldValue != lengthResolution {
                _updateData = true
            }
        }
    }

    public var depthResolution: Int {
        didSet {
            if oldValue != depthResolution {
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

    public init(
        context: Context,
        width: Float,
        length: Float,
        depth: Float,
        radius: Float,
        widthResolution: Int = 1,
        lengthResolution: Int = 1,
        depthResolution: Int = 1,
        angularResolution: Int = 24
    ) {
        self.width = width
        self.length = length
        self.depth = depth
        self.radius = radius
        self.widthResolution = widthResolution
        self.lengthResolution = lengthResolution
        self.depthResolution = depthResolution
        self.angularResolution = angularResolution
        super.init(context: context)
    }

    override public func generateGeometryData() -> GeometryData {
        generateCycloramaGeometryData(
            width,
            length,
            depth,
            radius,
            Int32(widthResolution),
            Int32(lengthResolution),
            Int32(depthResolution),
            Int32(angularResolution)
        )
    }
}
