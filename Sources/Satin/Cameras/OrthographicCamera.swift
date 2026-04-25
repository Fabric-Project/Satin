//
//  OrthographicCamera.swift
//  Satin
//
//  Created by Reza Ali on 8/5/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

open class OrthographicCamera: Camera {
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

    public var left: Float = -1.0 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    public var right: Float = 1.0 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    public var top: Float = 1.0 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    public var bottom: Float = -1.0 {
        didSet {
            updateProjectionMatrix = true
        }
    }

    override public var projectionMatrix: matrix_float4x4 {
        get {
            if updateProjectionMatrix {
                _projectionMatrix = orthographicMatrixf(left, right, bottom, top, near, far)
                updateProjectionMatrix = false
            }
            return _projectionMatrix
        }
        set {
            _projectionMatrix = newValue
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

    override public init(label: String = "Orthographic Camera") {
        super.init(label: label)
        left = -1
        right = 1
        bottom = -1
        top = 1
        near = 0.0
        far = 100
    }

    public init(label: String = "Orthographic Camera", left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        super.init(label: label)
        self.left = left
        self.right = right
        self.bottom = bottom
        self.top = top
        self.near = near
        self.far = far
    }

    public func update(left: Float, right: Float, bottom: Float, top: Float) {
        self.left = left
        self.right = right
        self.bottom = bottom
        self.top = top
    }

    public func update(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        self.left = left
        self.right = right
        self.bottom = bottom
        self.top = top
        self.near = near
        self.far = far
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        left = try values.decode(Float.self, forKey: .left)
        right = try values.decode(Float.self, forKey: .right)
        bottom = try values.decode(Float.self, forKey: .bottom)
        top = try values.decode(Float.self, forKey: .top)
        near = try values.decode(Float.self, forKey: .near)
        far = try values.decode(Float.self, forKey: .far)
    }

    override open func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
        try container.encode(bottom, forKey: .bottom)
        try container.encode(top, forKey: .top)
        try container.encode(near, forKey: .near)
        try container.encode(far, forKey: .far)
    }

    private enum CodingKeys: String, CodingKey {
        case left
        case right
        case bottom
        case top
        case near
        case far
    }

    override public func setFrom(object: Object, world: Bool = false) {
        super.setFrom(object: object, world: world)
        if let camera = object as? OrthographicCamera {
            left = camera.left
            right = camera.right
            bottom = camera.bottom
            top = camera.top
        }
    }
}
