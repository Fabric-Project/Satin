//
//  EncodingContext.swift
//  Satin
//

import Metal

/// What an object's `encode(in:)` records GPU work with: the submission's ordered commands, frame and
/// views, and storage in its frame arena. Work written to a slice allocated here stays valid, and
/// distinct from any other encode's, until the command buffer completes, so encoding one object
/// twice before either draw executes never overwrites the first result.
public struct EncodingContext {
    public let commands: GPUCommandRecording
    public var device: MTLDevice { commands.device }
    public let frame: FrameTime
    /// The submission's views: the cameras as they were when it was made, as its draws see them.
    public let views: [RenderView]
    let recorder: PacketRecorder

    init(commandBuffer: MTLCommandBuffer, frame: FrameTime, views: [RenderView], recorder: PacketRecorder) {
        self.init(commands: GPUCommandRecording(commandBuffer: commandBuffer), frame: frame, views: views, recorder: recorder)
    }

    init(commands: GPUCommandRecording, frame: FrameTime, views: [RenderView], recorder: PacketRecorder) {
        self.commands = commands
        self.frame = frame
        self.views = views
        self.recorder = recorder
    }

    /// `length` bytes, aligned for any buffer binding, valid until the command buffer completes.
    public func allocate(length: Int) -> (buffer: MTLBuffer, offset: Int) {
        let slice = recorder.allocate(length: length)
        return (buffer: slice.buffer, offset: slice.offset)
    }
}
