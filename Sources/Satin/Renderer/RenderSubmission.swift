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
        /// The builder has not recorded its render operation.
        case notRecorded
        /// An attachment the descriptor supplies doesn't have the destination's pixel format.
        case destinationMismatch(attachment: String, expected: MTLPixelFormat, found: MTLPixelFormat)
        /// Drawn by an encoder other than the one that made it.
        case foreignEncoder
    }

    let builder: SubmissionBuilder
    public let commandBuffer: MTLCommandBuffer
    public var frame: FrameTime { builder.frame }
    public var destination: RenderDestination { builder.destination }
    var configuration: SubmissionConfiguration { builder.configuration }
    var cameras: [Camera] { builder.cameras }
    var viewports: [MTLViewport] { builder.viewports }
    var simdViewports: [simd_float4] { builder.simdViewports }
    var views: [RenderView] { builder.views }
    var recorder: PacketRecorder { builder.recorder }
    var encoder: RenderEncoder { builder.encoder }
    var isConsumed: Bool { builder.isConsumed }

    init(builder: SubmissionBuilder, commandBuffer: MTLCommandBuffer) {
        self.builder = builder
        self.commandBuffer = commandBuffer
    }

    public func record(scene: Object) throws { try builder.recordAdditional(scene: scene) }

    public var encodingContext: EncodingContext {
        EncodingContext(commandBuffer: commandBuffer, frame: frame, views: views, recorder: recorder)
    }

    public func retainUntilCompleted(_ owner: AnyObject) { encoder.retainUntilCompleted(owner, commandBuffer: commandBuffer) }
}
