//
//  Camera.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import simd

open class Camera: Object {
    // MARK: - View

    /// A view assigned through `viewMatrix`, kept exactly until the camera's world transform changes
    /// after it (the assignment itself moves the camera to match).
    private var assignedView: (matrix: matrix_float4x4, worldRevision: UInt64)?
    private var computedView = matrix_identity_float4x4
    private var computedViewRevision: UInt64 = .max
    /// Advances with every view assignment, for caches derived from the view.
    private var viewAssignmentRevision: UInt64 = 0

    /// The inverse of the world matrix, or an assigned view until the camera moves after it.
    public final var viewMatrix: matrix_float4x4 {
        get {
            let revision = worldRevision
            if let assignedView, assignedView.worldRevision == revision {
                return assignedView.matrix
            }
            if computedViewRevision != revision {
                computedView = worldMatrixInverse
                computedViewRevision = revision
            }
            return computedView
        }
        set {
            localMatrix = newValue.inverse
            assignedView = (newValue, worldRevision)
            viewAssignmentRevision &+= 1
        }
    }

    private var computedViewDirection = simd_float3(0, 0, -1)
    private var computedViewDirectionRevision: UInt64 = .max
    public var viewDirection: simd_float3 {
        let revision = worldRevision
        if computedViewDirectionRevision != revision {
            computedViewDirection = simd_normalize(simd_make_float3(worldMatrix * simd_make_float4(0.0, 0.0, -1.0, 0.0)))
            computedViewDirectionRevision = revision
        }
        return computedViewDirection
    }

    // MARK: - Projection

    /// Advances when a projection input changes value: `near`, `far`, and a subclass's own (field
    /// of view, aspect, lens shift, extents).
    public private(set) var projectionInputsRevision: UInt64 = 0
    /// Advances whenever the effective projection may change: an input, or an assignment.
    private var projectionRevision: UInt64 = 0
    /// A projection assigned through `projectionMatrix` (or ARKit), kept exactly until a
    /// projection input changes after it.
    private var assignedProjection: (matrix: matrix_float4x4, inputsRevision: UInt64)?
    private var computedProjection = matrix_identity_float4x4
    private var computedProjectionInputsRevision: UInt64 = .max

    /// Subclasses call this when one of their projection inputs changes value. Rebuilding the
    /// projection never calls it.
    func projectionInputsDidChange() {
        projectionInputsRevision &+= 1
        projectionRevision &+= 1
    }

    /// The projection the inputs describe. Subclasses override.
    open func computeProjectionMatrix() -> matrix_float4x4 {
        matrix_identity_float4x4
    }

    /// Sets the inputs that `matrix` implies, when it is assigned. Subclasses override; inputs set
    /// here come before the assignment, so they don't replace it.
    open func adoptProjectionInputs(from matrix: matrix_float4x4) {}

    /// The projection the inputs describe, or an assigned one until an input changes after it.
    public final var projectionMatrix: matrix_float4x4 {
        get {
            if let assignedProjection, assignedProjection.inputsRevision == projectionInputsRevision {
                return assignedProjection.matrix
            }
            if computedProjectionInputsRevision != projectionInputsRevision {
                computedProjection = computeProjectionMatrix()
                computedProjectionInputsRevision = projectionInputsRevision
            }
            return computedProjection
        }
        set {
            adoptProjectionInputs(from: newValue)
            assignProjection(newValue)
        }
    }

    /// Records `matrix` as the projection, as of the current inputs.
    func assignProjection(_ matrix: matrix_float4x4) {
        assignedProjection = (matrix, projectionInputsRevision)
        projectionRevision &+= 1
    }

    public var near: Float = 0.01 {
        didSet {
            if near != oldValue { projectionInputsDidChange() }
        }
    }

    public var far: Float = 100.0 {
        didSet {
            if far != oldValue { projectionInputsDidChange() }
        }
    }

    // MARK: - View Projection

    private var computedViewProjection = matrix_identity_float4x4
    private var computedViewProjectionKey: (projection: UInt64, world: UInt64, viewAssignment: UInt64)?

    public var viewProjectionMatrix: matrix_float4x4 {
        let key = (projection: projectionRevision, world: worldRevision, viewAssignment: viewAssignmentRevision)
        if let computedViewProjectionKey, computedViewProjectionKey == key {
            return computedViewProjection
        }
        computedViewProjection = simd_mul(projectionMatrix, viewMatrix)
        computedViewProjectionKey = key
        return computedViewProjection
    }

    // MARK: - Motion

    /// The view-projection at the frame this camera was last drawn from, and the one before it, so
    /// every renderable and pass in a frame reads the same previous value.
    private var motionFrameNumber: Int?
    private var motionViewProjectionMatrix = matrix_identity_float4x4
    private var motionPreviousViewProjectionMatrix = matrix_identity_float4x4

    /// The view-projection this camera had in the frame before `frame`, or its current one when it
    /// wasn't drawn from then. Advances once per frame, on the first draw of that frame.
    public func previousViewProjectionMatrix(frame: FrameTime) -> simd_float4x4 {
        if motionFrameNumber != frame.frameNumber {
            let current = viewProjectionMatrix
            if let motionFrameNumber, motionFrameNumber == frame.frameNumber - 1 {
                motionPreviousViewProjectionMatrix = motionViewProjectionMatrix
            } else {
                motionPreviousViewProjectionMatrix = current
            }
            motionViewProjectionMatrix = current
            motionFrameNumber = frame.frameNumber
        }
        return motionPreviousViewProjectionMatrix
    }

    public init(context: Context, label: String = "Camera") {
        super.init(context: context, label: label)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        near = try values.decode(Float.self, forKey: .near)
        far = try values.decode(Float.self, forKey: .far)
    }

    override open func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(near, forKey: .near)
        try container.encode(far, forKey: .far)
    }

    private enum CodingKeys: String, CodingKey {
        case near
        case far
    }

    // Projects a coordinate from world space into the camera's normalized device coordinate (NDC) space.

    open func project(_ worldCoordinate: simd_float3) -> simd_float2 {
        var wc = simd_make_float4(worldCoordinate, 1.0)
        wc = viewProjectionMatrix * wc
        return simd_make_float2(wc) / wc.w
    }

    // Projects a point from world space into the camera's normalized device coordinate (NDC) space.

    open func project(_ worldCoordinate: simd_float3, _ viewSize: simd_float2) -> simd_float2 {
        return viewSize * ((project(worldCoordinate) + 1.0) * 0.5)
    }

    // Projects a point from the camera's normalized device coordinate (NDC) space into world space.
    open func unProject(_ ndcCoordinate: simd_float2) -> simd_float3 {
        let wc = worldMatrix * projectionMatrix.inverse * simd_make_float4(ndcCoordinate.x, ndcCoordinate.y, far / (far - near), 1.0)
        return simd_make_float3(wc) / wc.w
    }

    override public func setFrom(object: Object, world: Bool = false) {
        super.setFrom(object: object, world: world)
        if let camera = object as? Camera {
            near = camera.near
            far = camera.far
        }
    }

    override public func lookAt(target: simd_float3, up: simd_float3 = Satin.worldUpDirection, local: Bool = true) {
        if local {
            let zAxis = simd_normalize(position - target)
            let xAxis = simd_normalize(simd_cross(up, zAxis))
            let yAxis = simd_normalize(simd_cross(zAxis, xAxis))
            orientation = simd_quatf(simd_float3x3(xAxis, yAxis, zAxis))
        }
        else {
            let zAxis = simd_normalize(worldPosition - target)
            let xAxis = simd_normalize(simd_cross(up, zAxis))
            let yAxis = simd_normalize(simd_cross(zAxis, xAxis))
            worldOrientation = simd_quatf(simd_float3x3(xAxis, yAxis, zAxis))
        }
    }
}
