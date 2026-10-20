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

#if SWIFT_PACKAGE
import SatinCore
#endif

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
    /// Whether the map must be drawn again. Cleared when its passes are recorded; a producer that
    /// abandons that recording (`RenderEncoder.abandon(_:)`) sets it again.
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
        [camera.viewProjectionMatrix]
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
    
    // MARK: - Passes

    // A shadow draws one depth pass per view: a point light's six faces, otherwise one. Its
    // casters are recorded once for every pass of every shadow drawn in a frame (see
    // `ShadowCasterRecording`), and each pass encodes them as its own view.

    /// How many passes, and views, this shadow draws.
    var passCount: Int { 1 }

    /// The camera pass `passIndex` sees from.
    func passCamera(_ passIndex: Int) -> Camera { camera }

    /// The depth texture pass `passIndex` draws into.
    func passTexture(_ passIndex: Int) -> MTLTexture? { texture }

    /// Makes what the passes draw into, before any pass begins.
    func prepareForDrawing(context: Context) {}

    /// Whether a caster within `bounds` may reach any of this shadow's passes, beyond what each
    /// pass's frustum says: a point light's far planes. True when it can't tell.
    func mayReach(_ bounds: Bounds) -> Bool { true }

    /// The viewport every pass draws with: the whole map.
    var passViewport: simd_float4 {
        simd_make_float4(0.0, 0.0, Float(resolution.width), Float(resolution.height))
    }

}

