//
//  PerspectiveCamera.swift
//  Satin
//
//  Created by Reza Ali on 8/15/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

open class PerspectiveCamera: Camera {
    @Published public var fov: Float = 45 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    @Published public var aspect: Float = 1 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    @Published public var lensShiftX: Float = 0.0 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    @Published public var lensShiftY: Float = 0.0 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    @Published public var enableFrustumShift: Bool = false {
        didSet {
            updateProjectionMatrix = true
        }
    }

    override public var scale: simd_float3 {
        didSet {
            updateViewMatrix = true
            updateWorldMatrix = true
        }
    }

    override public var position: simd_float3 {
        didSet {
            updateViewMatrix = true
            updateWorldMatrix = true
        }
    }

    override public var orientation: simd_quatf {
        didSet {
            updateViewMatrix = true
            updateWorldMatrix = true
        }
    }

    override public var projectionMatrix: matrix_float4x4 {
        get {
            if updateProjectionMatrix {
                if enableFrustumShift {
                    _projectionMatrix = frustumShiftPerspectiveMatrixf(fov, aspect, near, far, lensShiftX, lensShiftY)
                } else {
                    _projectionMatrix = perspectiveMatrixf(fov, aspect, near, far)
                }
                updateProjectionMatrix = false
            }
            return _projectionMatrix
        }
        set {
            _projectionMatrix = newValue
            let col0 = newValue.columns.0
            let col1 = newValue.columns.1
            let col2 = newValue.columns.2
            let col3 = newValue.columns.3
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
    }

    override public var viewMatrix: matrix_float4x4 {
        get {
            if updateViewMatrix {
                _viewMatrix = worldMatrixInverse
                updateViewMatrix = false
            }
            return _viewMatrix
        }
        set {
            _viewMatrix = newValue
            localMatrix = newValue.inverse
        }
    }

    public convenience init(label: String = "Perspective Camera", position: simd_float3, near: Float, far: Float, fov: Float = 45) {
        self.init(label: label)
        self.position = position
        self.near = near
        self.far = far
        self.fov = fov
    }

    override public init(label: String = "Perspective Camera") {
        super.init(label: label)
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

    public func setProjectionMatrixFromARKit(_ newValue: matrix_float4x4) {
        _projectionMatrix = newValue

        let col0 = newValue.columns.0
        let col1 = newValue.columns.1
        fov = radToDeg(2.0 * atan(1.0 / col1.y))
        aspect = col1.y / col0.x

        let farMinusNear = far - near
        let sz = near / farMinusNear
        let sw = (far * near) / farMinusNear

        _projectionMatrix.columns.2.x = 0.0
        _projectionMatrix.columns.2.y = 0.0
        _projectionMatrix.columns.2.z = sz
        _projectionMatrix.columns.3.z = sw
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
