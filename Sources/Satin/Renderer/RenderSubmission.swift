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
    /// Queued drawing requires a caller buffer that has not reserved its GPU queue position yet.
    case commandBufferAlreadyEnqueued
    /// Metal could not create the private command buffer for a queued submission.
    case commandBufferUnavailable
    /// The builder was already sealed, or the sealed submission already encoded or abandoned.
    case alreadyDrawn
    /// The builder has not recorded its render operation.
    case notRecorded
    /// An attachment the descriptor supplies doesn't have the destination's pixel format.
    case destinationMismatch(attachment: String, expected: MTLPixelFormat, found: MTLPixelFormat)
}
