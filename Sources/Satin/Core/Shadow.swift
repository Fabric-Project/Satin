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
    
    /// Per-frame render snapshot fields for shadow scalars, written by `prepareForRender()` on the render owner. Never mutated from authoring code during encoding. Read by `data` to produce `ShadowData` for the current frame.
    internal var renderSnapshotStrength: Float = 1.0
    internal var renderSnapshotBias: Float = 0.00001
    internal var renderSnapshotNormalBias: Float = 0.00001
    internal var renderSnapshotRadius: Float = 1.0

    public var data: ShadowData {
        ShadowData(strength: renderSnapshotStrength, bias: renderSnapshotBias, normalBias: renderSnapshotNormalBias, radius: renderSnapshotRadius)
    }

    func prepareForRender() {
        renderSnapshotStrength = strength
        renderSnapshotBias = bias
        renderSnapshotNormalBias = normalBias
        renderSnapshotRadius = radius
    }

    public var camera: Camera
    public var resolution: (width: Int, height: Int) = (width:1024, height:1024)

    public var enabled = true
    public var autoUpdate = true
    public var needsUpdate = true

    public var strength: Float = 1.0
    public var bias: Float = 0.00001
    public var normalBias: Float = 0.00001
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
        [camera.renderSnapshotViewProjectionMatrix]
    }

    public var viewCount: Int {
        1
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
