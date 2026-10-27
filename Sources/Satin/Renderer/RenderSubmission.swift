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

/// Why recording, sealing or encoding a submission failed.
public enum SubmissionError: Swift.Error, Equatable {
    /// The builder was sealed or discarded after failure, or the sealed submission was encoded or abandoned.
    case alreadyDrawn
    /// The builder has not recorded its render operation.
    case notRecorded
    case renderCommandEncoderCreationFailed
    case shadowAllocationFailed
    case pipelineCompilationFailed
    /// An attachment the descriptor supplies doesn't have the destination's pixel format.
    case destinationMismatch(attachment: String, expected: MTLPixelFormat, found: MTLPixelFormat)
}
