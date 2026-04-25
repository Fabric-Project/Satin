//
//  ARPerspectiveCamera.swift
//  Example
//
//  Created by Reza Ali on 3/16/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import simd
import UIKit

open class ARPerspectiveCamera: PerspectiveCamera {
    unowned var session: ARSession
    unowned var metalView: MetalView

    public private(set) var intrinsics: matrix_float3x3 = matrix_identity_float3x3
    public private(set) var localToWorld: matrix_float4x4 = matrix_identity_float4x4

    public init(context: Context, session: ARSession, metalView: MetalView, near: Float, far: Float) {
        self.session = session
        self.metalView = metalView
        super.init(context: context)
        label = "AR Perspective Camera"
        self.near = near
        self.far = far
    }

    public required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    override open func update() {
        super.update()
        guard let frame = session.currentFrame,
              let orientation = UIWindow.keyWindow?.windowScene?.interfaceOrientation else { return }

        viewMatrix = frame.camera.viewMatrix(for: orientation)
        let arkitProjectionMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: metalView.drawableSize, zNear: CGFloat(near), zFar: CGFloat(far))
        setProjectionMatrixFromARKit(arkitProjectionMatrix)

        localToWorld = viewMatrix.inverse * orientationCorrection(orientation: orientation)
        intrinsics = frame.camera.intrinsics
    }

    private let yzFlipMatrix = matrix_float4x4(
        simd_make_float4(1, 0, 0, 0),
        simd_make_float4(0, -1, 0, 0),
        simd_make_float4(0, 0, -1, 0),
        simd_make_float4(0, 0, 0, 1)
    )

    private func orientationCorrection(orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        return yzFlipMatrix * matrix_float4x4(
            simd_quatf(
                angle: cameraToDisplayRotation(orientation: orientation),
                axis: Satin.worldForwardDirection
            )
        )
    }

    private func cameraToDisplayRotation(orientation: UIInterfaceOrientation) -> Float {
        switch orientation {
            case .landscapeLeft:
                return Float.pi
            case .portrait:
                return Float.pi * 0.5
            case .portraitUpsideDown:
                return -Float.pi * 0.5
            default:
                return 0
        }
    }
}

#endif
