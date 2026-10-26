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
    let recordingState = ShadowRecordingState()
    var recordedVersion: RecordedShadow?
    public var needsUpdate: Bool {
        get { recordingState.needsUpdate }
        set {
            if newValue { recordingState.requestUpdate() }
            else { recordingState.markRecorded(revision: recordingState.revision) }
        }
    }

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
        enabled && (autoUpdate || needsUpdate || recordingState.hasUnencodedVersion)
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

    /// A captured occurrence keeps its map immutable. Detach that destination before a later
    /// native pass redraws it; ordinary ordered passes without captured maps keep their reuse path.
    func beginRecording(context: Context) throws {
        prepareForDrawing(context: context)
        if recordedVersion != nil, let texture {
            self.texture = try makeShadowTextureVersion(of: texture, device: context.device)
        }
        recordedVersion = nil
        recordingState.captureVersion()
    }

    var recordingInvalidation: ShadowRecordingInvalidation {
        ShadowRecordingInvalidation(state: recordingState, generation: recordingState.generation)
    }

    func adoptRecordedVersion(_ version: RecordedShadow) {
        recordedVersion = version
        texture = version.textures.first
    }

    /// Conservative world-space reach shared by all passes, captured with recorded shadows.
    /// Nil means the pass frusta alone determine reach.
    var reachBounds: Bounds? { nil }

    /// Whether a caster may reach any pass, including far planes omitted by the pass frusta.
    func mayReach(_ bounds: Bounds) -> Bool {
        guard let reachBounds else { return true }
        return ViewFrustum.mayIntersect(bounds, reachBounds)
    }

    /// The viewport every pass draws with: the whole map.
    var passViewport: simd_float4 {
        simd_make_float4(0.0, 0.0, Float(resolution.width), Float(resolution.height))
    }

}

/// Shared without retaining the source Shadow: a captured map can mark its exact source revision
/// clean, while a light moved by a later iteration remains dirty. This creates no ownership cycle.
final class ShadowRecordingState {
    private(set) var revision: UInt64 = 0
    private(set) var generation: UInt64 = 0
    private var recordedRevision: UInt64?
    private var encodedGeneration: UInt64?
    var hasUnencodedVersion: Bool { generation != 0 && encodedGeneration != generation }
    var needsUpdate: Bool { recordedRevision != revision }
    func requestUpdate() { revision &+= 1 }
    @discardableResult
    func captureVersion() -> UInt64 { generation &+= 1; return generation }
    func markRecorded(revision: UInt64, generation: UInt64? = nil) {
        if revision == self.revision && (generation == nil || generation == self.generation) {
            recordedRevision = revision
        }
    }
    func markEncoded(generation: UInt64) {
        if generation == self.generation { encodedGeneration = generation }
    }
    func invalidate(generation: UInt64) {
        if generation == self.generation { requestUpdate() }
    }
}

struct ShadowRecordingInvalidation {
    let state: ShadowRecordingState
    let generation: UInt64
    func invalidate() { state.invalidate(generation: generation) }
    func markEncoded() { state.markEncoded(generation: generation) }
}

