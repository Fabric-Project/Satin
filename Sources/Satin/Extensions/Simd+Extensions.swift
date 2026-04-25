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
