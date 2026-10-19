//
//  RenderSubmission.swift
//  Satin
//

import Metal
import simd

/// The encoder settings a submission draws with, copied when it is made: changing the encoder
/// afterwards affects only later submissions.
struct SubmissionConfiguration {
    var renderingMode: RenderingMode
    var activeOutputs: RendererOutputs
    var sortObjects: Bool
    var clearColor: MTLClearColor
    var colorLoadAction: MTLLoadAction
    var colorStoreAction: MTLStoreAction
    var clearDepth: Double
    var depthLoadAction: MTLLoadAction
    var depthStoreAction: MTLStoreAction
    var clearStencil: UInt32
    var stencilLoadAction: MTLLoadAction
    var stencilStoreAction: MTLStoreAction
}

/// One rendering operation of one `RenderEncoder`: a frame, a command buffer, and the views it draws
/// from, fixed when the submission is made, before anything is updated or recorded.
///
/// `record(scene:)` captures a scene as it is at that moment: its objects' transforms, materials'
/// uniforms, instances and poses, snapshotted into the frame arena, so changing the scene afterwards
/// (as an Iterator does between iterations) doesn't alter what was recorded. Drawing the submission
/// updates and records its own scene, then encodes everything: per render layer, the scene's own
/// draws, then each record in call order. Records draw in the colour passes only, as they never
/// cast shadows.
///
/// The encoder's settings (rendering mode, outputs, sorting, clear and load/store actions) are
/// frozen when the submission is made, and so is its destination: the encoder's pixel formats.
///
/// A submission draws once, on the encoder that made it. Drawing consumes it: further `record` and
/// `draw` calls throw `.alreadyDrawn`. A draw rejected before doing any work (another encoder, or a
/// descriptor not matching the destination) leaves it unconsumed. One released without drawing gives its storage back.
public final class RenderSubmission {
    public enum Error: Swift.Error, Equatable {
        /// The submission was already drawn.
        case alreadyDrawn
        /// An attachment the descriptor supplies doesn't have the destination's pixel format.
        case destinationMismatch(attachment: String, expected: MTLPixelFormat, found: MTLPixelFormat)
        /// Drawn by an encoder other than the one that made it.
        case foreignEncoder
    }

    public let frame: FrameTime
    public let commandBuffer: MTLCommandBuffer
    /// The encoder's attachment formats and sample count when the submission was made.
    public let destination: RenderDestination
    let configuration: SubmissionConfiguration

    let cameras: [Camera]
    let viewports: [MTLViewport]
    let simdViewports: [simd_float4]
    /// The cameras as they were when the submission was made, with their previous view-projections.
    let views: [RenderView]
    let recorder: PacketRecorder

    /// The encoder that made it: the only one that may draw it.
    let encoder: RenderEncoder
    private let pool: PacketStoragePool
    private(set) var isConsumed = false

    init(encoder: RenderEncoder, pool: PacketStoragePool, recorder: PacketRecorder, frame: FrameTime, commandBuffer: MTLCommandBuffer, cameras: [Camera], viewports: [MTLViewport], destination: RenderDestination, configuration: SubmissionConfiguration) {
        self.encoder = encoder
        self.destination = destination
        self.configuration = configuration
        self.pool = pool
        self.recorder = recorder
        self.frame = frame
        self.commandBuffer = commandBuffer
        self.cameras = cameras
        self.viewports = viewports
        let simdViewports = viewports.map(\.float4)
        self.simdViewports = simdViewports
        var views: [RenderView] = []
        views.reserveCapacity(cameras.count)
        for (index, camera) in cameras.enumerated() {
            let viewport = simdViewports.isEmpty ? simd_float4.zero : simdViewports[min(index, simdViewports.count - 1)]
            views.append(RenderView(camera: camera, viewport: viewport, frame: frame))
        }
        self.views = views
    }

    deinit {
        if !isConsumed {
            pool.returnStorage(recorder.storage)
        }
    }

    /// Records `scene` as it is now into this submission. It updates and encodes nothing: update the
    /// scene, and encode its GPU work with `encodingContext`, first.
    public func record(scene: Object) throws {
        guard !isConsumed else { throw Error.alreadyDrawn }
        encoder.record(scene: scene, into: self)
    }

    /// For encoding GPU work that this submission's records draw, such as an Iterator's
    /// per-iteration `encode(in:)`.
    public var encodingContext: EncodingContext {
        EncodingContext(commandBuffer: commandBuffer, frame: frame, views: views, recorder: recorder)
    }

    /// Keeps `owner` alive until this submission's command buffer completes, or until its arena
    /// region is reclaimed if the command buffer is never committed: for resources a recorded draw
    /// uses that nothing else holds.
    public func retainUntilCompleted(_ owner: AnyObject) {
        recorder.retainUntilCompleted(owner)
    }

    /// Marks the submission drawn. False when it already was.
    func consume() -> Bool {
        guard !isConsumed else { return false }
        isConsumed = true
        return true
    }

    /// Gives the storage back once its draws are encoded. Called once, by the draw that consumed it.
    func returnStorage() {
        pool.returnStorage(recorder.storage)
    }
}
