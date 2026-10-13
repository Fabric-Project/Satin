//
//  Simd+Extensions.swift
//  Satin
//
//  Created by Reza Ali on 9/14/19.
//

import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

extension MTLPackedFloat3: @retroactive Equatable {
    public static func == (lhs: _MTLPackedFloat3, rhs: _MTLPackedFloat3) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }

    public subscript(index: Int) -> Float {
        get {
            if index == 0 {
                return self.x
            }
            else if index == 1 {
                return self.y
            }
            else {
                return self.z
            }
        }
        set {
            if index == 0 {
                self.x = newValue
            }
            else if index == 1 {
                self.y = newValue
            }
            else if index == 2 {
                self.z = newValue
            }
        }
    }
}

extension MTLPackedFloat3: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        let data = try values.decode(simd_float3.self)
        self.init()
        self.x = data.x
        self.y = data.y
        self.z = data.z
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([x, y, z])
    }
}

extension simd_quatf: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        try self.init(vector: values.decode(simd_float4.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.vector)
    }
}

extension simd_float4x4: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        try self.init(values.decode([simd_float4].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([columns.0, columns.1, columns.2, columns.3])
    }
}

public extension simd_float4x4 {
    /// Composes scale first, then rotation, then translation, as USD composes a joint's transform.
    init(translation: simd_float3 = .zero, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: simd_float3 = .one) {
        self.init(simd_normalize(rotation))
        columns.0 *= scale.x
        columns.1 *= scale.y
        columns.2 *= scale.z
        columns.3 = simd_float4(translation, 1)
    }

    /// A transform as translation, rotation and scale, as `init(translation:rotation:scale:)` composes it.
    typealias Decomposition = (translation: simd_float3, rotation: simd_quatf, scale: simd_float3)

    /// Splits into translation, rotation and scale; shear is not kept. A mirrored matrix (negative
    /// determinant) keeps its handedness as a negative x scale. An axis scaled to zero keeps its
    /// zero scale and takes a direction square to the others, so the rotation stays a rotation.
    var decomposed: Decomposition {
        var xAxis = simd_make_float3(columns.0)
        var yAxis = simd_make_float3(columns.1)
        var zAxis = simd_make_float3(columns.2)
        var scale = simd_float3(simd_length(xAxis), simd_length(yAxis), simd_length(zAxis))
        if simd_dot(simd_cross(xAxis, yAxis), zAxis) < 0 { scale.x = -scale.x }
        let translation = simd_make_float3(columns.3)

        // Shorter than a millionth of the longest axis: no direction left to keep.
        let collapsedLength = max(simd_reduce_max(simd_abs(scale)) * 1e-6, .leastNormalMagnitude)
        let xCollapsed = abs(scale.x) <= collapsedLength
        let yCollapsed = abs(scale.y) <= collapsedLength
        let zCollapsed = abs(scale.z) <= collapsedLength
        // Dividing by the signed scale also turns a mirrored x axis back.
        if !xCollapsed { xAxis /= scale.x }
        if !yCollapsed { yAxis /= scale.y }
        if !zCollapsed { zAxis /= scale.z }
        switch (xCollapsed, yCollapsed, zCollapsed) {
        case (false, false, false):
            break
        case (true, false, false):
            xAxis = simd_normalize(simd_cross(yAxis, zAxis))
        case (false, true, false):
            yAxis = simd_normalize(simd_cross(zAxis, xAxis))
        case (false, false, true):
            zAxis = simd_normalize(simd_cross(xAxis, yAxis))
        case (false, true, true):
            yAxis = Self.perpendicular(to: xAxis)
            zAxis = simd_cross(xAxis, yAxis)
        case (true, false, true):
            zAxis = Self.perpendicular(to: yAxis)
            xAxis = simd_cross(yAxis, zAxis)
        case (true, true, false):
            xAxis = Self.perpendicular(to: zAxis)
            yAxis = simd_cross(zAxis, xAxis)
        case (true, true, true):
            return (translation, simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale)
        }
        return (translation, simd_quatf(simd_float3x3(xAxis, yAxis, zAxis)), scale)
    }

    /// A unit vector square to `axis`.
    private static func perpendicular(to axis: simd_float3) -> simd_float3 {
        let reference: simd_float3 = abs(axis.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
        return simd_normalize(simd_cross(axis, reference))
    }

    init(textureTransform transform: simd_float3x3) {
        self.init(
            simd_float4(transform.columns.0.x, transform.columns.0.y, 0.0, 0.0),
            simd_float4(transform.columns.1.x, transform.columns.1.y, 0.0, 0.0),
            simd_float4(0.0, 0.0, 1.0, 0.0),
            simd_float4(transform.columns.2.x, transform.columns.2.y, 0.0, 1.0)
        )
    }

    static var textureVerticalFlip: simd_float4x4 {
        simd_float4x4(
            simd_float4(1.0, 0.0, 0.0, 0.0),
            simd_float4(0.0, -1.0, 0.0, 0.0),
            simd_float4(0.0, 0.0, 1.0, 0.0),
            simd_float4(0.0, 1.0, 0.0, 1.0)
        )
    }

    static func textureTransform(
        offset: simd_float2 = .zero,
        scale: simd_float2 = simd_float2(repeating: 1.0),
        rotation: Float = 0.0
    ) -> simd_float4x4 {
        let ct = cos(rotation)
        let st = sin(rotation)

        let rotationTransform = simd_float4x4(
            simd_float4(ct, st, 0.0, 0.0),
            simd_float4(-st, ct, 0.0, 0.0),
            simd_float4(0.0, 0.0, 1.0, 0.0),
            simd_float4(0.0, 0.0, 0.0, 1.0)
        )

        let offsetTransform = simd_float4x4(
            simd_float4(1.0, 0.0, 0.0, 0.0),
            simd_float4(0.0, 1.0, 0.0, 0.0),
            simd_float4(0.0, 0.0, 1.0, 0.0),
            simd_float4(offset.x, offset.y, 0.0, 1.0)
        )

        let scaleTransform = simd_float4x4(
            simd_float4(scale.x, 0.0, 0.0, 0.0),
            simd_float4(0.0, scale.y, 0.0, 0.0),
            simd_float4(0.0, 0.0, 1.0, 0.0),
            simd_float4(0.0, 0.0, 0.0, 1.0)
        )

        return rotationTransform * scaleTransform * offsetTransform
    }

    func act(_ ray: Ray) -> Ray {
        let transformedOrigin = simd_make_float3(self * simd_make_float4(ray.origin, 1.0))
        let transformedDirection = simd_make_float3(self * simd_make_float4(ray.direction))
        return Ray(origin: transformedOrigin, direction: simd_normalize(transformedDirection))
    }
}

extension simd_float3x3: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        try self.init(values.decode([simd_float3].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([columns.0, columns.1, columns.2])
    }
}

extension simd_float2x2:@retroactive Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        try self.init(values.decode([simd_float2].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([columns.0, columns.1])
    }
}
