//
//  LightShadow.swift
//  Satin
//
//  Created by Reza Ali on 3/2/23.
//

import Combine
import Foundation
import Metal
import simd

public class Shadow {
    public var label: String
    public var texture: MTLTexture? = nil
    
    public var data: ShadowData {
        ShadowData(strength: strength, bias: bias, normalBias: normalBias, radius: radius)
    }

    public var camera: Camera
    public var resolution: (width: Int, height: Int) = (width:1024, height:1024)

    public var enabled = true
    public var autoUpdate = true
    public var needsUpdate = true

    public var strength: Float = 1.0
    public var bias: Float = 0.00001
    public var normalBias: Float = 0.0
    public var radius: Float =  1.0

    public var texturePublisher = PassthroughSubject<Shadow, Never>()
    public var resolutionPublisher = PassthroughSubject<Shadow, Never>()
    public var dataPublisher = PassthroughSubject<Shadow, Never>()

    
    init(context: Context, label: String) {
        self.label = label
        camera = OrthographicCamera(context: context, left: -5, right: 5, bottom: -5, top: 5, near: 0.01, far: 50.0)
    }

    public var textures: [MTLTexture] {
        guard let texture else { return [] }
        return [texture]
    }

    public var matrices: [simd_float4x4] {
        [camera.viewProjectionMatrix]
    }

    public var viewCount: Int {
        1
    }

    public var isLegacyPlanarCompatible: Bool {
        viewCount == 1
    }
    
    public func update(light: Object) {
        needsUpdate = true
    }

    public var shouldRender: Bool {
        enabled && (autoUpdate || needsUpdate)
    }
    
    public func draw(context: Context, commandBuffer: MTLCommandBuffer, renderables: [Renderable]) {
        fatalError("Subclasses must overload")
    }
}

struct ShadowRenderable {
    let renderable: Renderable
    let cullMode: MTLCullMode?
    let windingOrder: MTLWinding?
    let triangleFillMode: MTLTriangleFillMode?
}

// Gribb/Hartmann frustum planes from a Metal view-projection matrix (NDC z ∈ [0,1]).
struct ShadowFrustum {
    private let planes: (simd_float4, simd_float4, simd_float4, simd_float4, simd_float4, simd_float4)

    init(_ vpMatrix: simd_float4x4) {
        let M = vpMatrix
        let r0 = simd_float4(M.columns.0.x, M.columns.1.x, M.columns.2.x, M.columns.3.x)
        let r1 = simd_float4(M.columns.0.y, M.columns.1.y, M.columns.2.y, M.columns.3.y)
        let r2 = simd_float4(M.columns.0.z, M.columns.1.z, M.columns.2.z, M.columns.3.z)
        let r3 = simd_float4(M.columns.0.w, M.columns.1.w, M.columns.2.w, M.columns.3.w)
        planes = (r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2, r3 - r2)
    }

    // Returns false if the AABB is fully outside any single frustum half-space.
    func contains(_ bounds: Bounds) -> Bool {
        let corners = (0..<8).map { boundsCorner(bounds, Int32($0)) }
        for plane in [planes.0, planes.1, planes.2, planes.3, planes.4, planes.5] {
            if corners.allSatisfy({ simd_dot(plane, $0) < 0 }) { return false }
        }
        return true
    }
}

extension Shadow {
    // Pass a frustum to cull by shadow volume. For single-camera shadows (directional, spot)
    // pass the camera frustum. For point shadows, pass nil here and cull per-face in the draw loop.
    func shadowRenderables(context: Context, renderables: [Renderable], frustum: ShadowFrustum? = nil) -> [ShadowRenderable] {
        renderables.compactMap { renderable in
            guard renderable.castShadow, renderable.isDrawable(renderContext: context, shadow: true) else { return nil }
            if let frustum, !frustum.contains(renderable.worldBounds) { return nil }
            return ShadowRenderable(
                renderable: renderable,
                cullMode: renderable.cullMode,
                windingOrder: renderable.windingOrder,
                triangleFillMode: renderable.triangleFillMode
            )
        }
    }
}
