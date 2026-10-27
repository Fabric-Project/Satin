//
//  EncodingContext.swift
//  Satin
//

import Metal

/// What an object's `encode(in:)` encodes GPU work with: the submission's command buffer, frame and
/// views, and storage in its frame arena. Work written to a slice allocated here stays valid, and
/// distinct from any other encode's, until the command buffer completes, so encoding one object
/// twice before either draw executes never overwrites the first result.
public struct EncodingContext {
    public let commandBuffer: MTLCommandBuffer
    public let frame: FrameTime
    /// The submission's views: the cameras as they were when it was made, as its draws see them.
    public let views: [RenderView]
    let recorder: PacketRecorder
    private let preparation: Int

    init(commandBuffer: MTLCommandBuffer, frame: FrameTime, views: [RenderView], recorder: PacketRecorder) {
        self.commandBuffer = commandBuffer
        self.frame = frame
        self.views = views
        self.recorder = recorder
        preparation = recorder.beginPreparation()
    }

    /// `length` bytes, aligned for any buffer binding, valid until the command buffer completes.
    public func allocate(length: Int) throws -> (buffer: MTLBuffer, offset: Int) {
        let slice = try recorder.allocate(length: length)
        recorder.retainArena(for: preparation, untilCompleted: commandBuffer)
        return (buffer: slice.buffer, offset: slice.offset)
    }
}
