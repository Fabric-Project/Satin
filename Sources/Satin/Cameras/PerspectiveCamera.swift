//
//  PerspectiveCamera.swift
//  Satin
//
//  Created by Reza Ali on 8/15/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

open class PerspectiveCamera: Camera {
    public var fov: Float = 45 {
        didSet {
            if fov != oldValue { projectionInputsDidChange() }
        }
    }

    public var aspect: Float = 1 {
        didSet {
            if aspect != oldValue { projectionInputsDidChange() }
        }
    }

    public var lensShiftX: Float = 0.0 {
        didSet {
            if lensShiftX != oldValue { projectionInputsDidChange() }
        }
    }

    public var lensShiftY: Float = 0.0 {
        didSet {
            if lensShiftY != oldValue { projectionInputsDidChange() }
        }
    }

    public var enableFrustumShift: Bool = false {
        didSet {
            if enableFrustumShift != oldValue { projectionInputsDidChange() }
        }
    }

    override open func computeProjectionMatrix() -> matrix_float4x4 {
        if enableFrustumShift {
            return frustumShiftPerspectiveMatrixf(fov, aspect, near, far, lensShiftX, lensShiftY)
        }
        return perspectiveMatrixf(fov, aspect, near, far)
    }

    /// The field of view, aspect, depth range and lens shift an assigned perspective matrix implies.
    override open func adoptProjectionInputs(from matrix: matrix_float4x4) {
        let col0 = matrix.columns.0
        let col1 = matrix.columns.1
        let col2 = matrix.columns.2
        let col3 = matrix.columns.3
        fov = radToDeg(2.0 * atan(1.0 / col1.y))
        aspect = col1.y / col0.x
        let sz = col2.z
        let sw = col3.z
        far = sw / sz
        near = sw / (1.0 + sz)

        if enableFrustumShift {
            lensShiftX = col2.x
            lensShiftY = col2.y
        }
    }

    public convenience init(context: Context, label: String = "Perspective Camera", position: simd_float3, near: Float, far: Float, fov: Float = 45) {
        self.init(context: context, label: label)
        self.position = position
        self.near = near
        self.far = far
        self.fov = fov
    }

    override public init(context: Context, label: String = "Perspective Camera") {
        super.init(context: context, label: label)
        orientation = simd_quatf(matrix_identity_float4x4)
        position = simd_make_float3(0.0, 0.0, 1.0)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fov = try values.decode(Float.self, forKey: .fov)
        aspect = try values.decode(Float.self, forKey: .aspect)
        lensShiftX = try values.decodeIfPresent(Float.self, forKey: .lensShiftX) ?? 0.0
        lensShiftY = try values.decodeIfPresent(Float.self, forKey: .lensShiftY) ?? 0.0
        enableFrustumShift = try values.decodeIfPresent(Bool.self, forKey: .enableFrustumShift) ?? false
    }

    override open func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fov, forKey: .fov)
        try container.encode(aspect, forKey: .aspect)
        try container.encode(lensShiftX, forKey: .lensShiftX)
        try container.encode(lensShiftY, forKey: .lensShiftY)
        try container.encode(enableFrustumShift, forKey: .enableFrustumShift)
    }

    private enum CodingKeys: String, CodingKey {
        case fov
        case aspect
        case lensShiftX
        case lensShiftY
        case enableFrustumShift
    }

    override public func setFrom(object: Object, world: Bool = false) {
        super.setFrom(object: object, world: world)
        if let camera = object as? PerspectiveCamera {
            fov = camera.fov
            aspect = camera.aspect
            lensShiftX = camera.lensShiftX
            lensShiftY = camera.lensShiftY
            enableFrustumShift = camera.enableFrustumShift
        }
    }

    /// Takes ARKit's projection: its field of view and aspect, with this camera's depth range and no
    /// principal-point offset. Kept until a projection input changes after it.
    public func setProjectionMatrixFromARKit(_ newValue: matrix_float4x4) {
        let col0 = newValue.columns.0
        let col1 = newValue.columns.1
        fov = radToDeg(2.0 * atan(1.0 / col1.y))
        aspect = col1.y / col0.x

        let farMinusNear = far - near
        var projection = newValue
        projection.columns.2.x = 0.0
        projection.columns.2.y = 0.0
        projection.columns.2.z = near / farMinusNear
        projection.columns.3.z = (far * near) / farMinusNear
        assignProjection(projection)
    }

    // MARK: - Frustum Shift
    public func setLensShift(_ x: Float, _ y: Float) {
        lensShiftX = x
        lensShiftY = y
        enableFrustumShift = x != 0.0 || y != 0.0
    }

    public func resetLensShift() {
        lensShiftX = 0.0
        lensShiftY = 0.0
        enableFrustumShift = false
    }
}
