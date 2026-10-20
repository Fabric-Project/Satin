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
    private var dirty = true
    private var recordedUpdate: ShadowUpdateCompletion?
    public var needsUpdate: Bool {
        get { dirty && !(recordedUpdate?.isComplete ?? false) }
        set {
            dirty = newValue
            if newValue { recordedUpdate = nil }
        }
    }

    /// Repeated recordings of one dirty generation share a completion token. The producer reads
    /// it; GPU completion mutates only the token, never this scene-owned Shadow.
    func recordingCompletion() -> ShadowUpdateCompletion {
        if let recordedUpdate { return recordedUpdate }
        let completion = ShadowUpdateCompletion()
        recordedUpdate = completion
        return completion
    }

    public var strength: Float = 1.0
    public var bias: Float = 0.00001
    public var normalBias: Float = 0.00001
    public var radius: Float =  1.0

    public var texturePublisher = PassthroughSubject<Shadow, Never>()
    public var resolutionPublisher = PassthroughSubject<Shadow, Never>()
    public var dataPublisher = PassthroughSubject<Shadow, Never>()

    /// The state of the shadow's render pass, reused by each pass it encodes.
    let renderEncoderState = RenderEncoderState()

    
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

    /// Starts pass `passIndex`: an encoder clearing its depth texture, with the pass's viewport
    /// set through `renderEncoderState`. Nil when there is nothing to draw into.
    func beginPass(_ passIndex: Int, context: Context, commandBuffer: MTLCommandBuffer) -> MTLRenderCommandEncoder? {
        guard let depthTexture = passTexture(passIndex) else { return nil }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.defaultRasterSampleCount = context.sampleCount
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .store
        renderPassDescriptor.depthAttachment.clearDepth = 0.0
        renderPassDescriptor.renderTargetWidth = resolution.width
        renderPassDescriptor.renderTargetHeight = resolution.height

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return nil }
        renderEncoder.label = passCount > 1 ? "\(label) Shadow Encoder \(passIndex)" : label + " Shadow Encoder"
        renderEncoderState.begin(renderEncoder: renderEncoder, renderPassDescriptor: renderPassDescriptor)
        renderEncoderState.setPassViewport(MTLViewport(originX: 0, originY: 0, width: Double(resolution.width), height: Double(resolution.height), znear: 0.0, zfar: 1.0))
        return renderEncoder
    }

    /// Ends the pass `beginPass` started.
    func endPass(_ renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.endEncoding()
        renderEncoderState.end()
    }
}

/// A generation of a shadow map, valid only after its GPU writes succeeded. It owns no Shadow.
final class ShadowUpdateCompletion {
    private let lock = UnfairLock()
    private var completed = false
    var isComplete: Bool { lock.sync { completed } }
    func complete(succeeded: Bool) {
        if succeeded { lock.sync { completed = true } }
    }
}
