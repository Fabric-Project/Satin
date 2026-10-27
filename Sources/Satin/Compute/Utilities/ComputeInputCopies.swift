//
//  ComputeInputCopies.swift
//  Satin
//

import Metal

/// Copies a dispatch's reflected read-only Satin-owned inputs (automatic uniforms, registered
/// `UniformBuffer` and `StructBuffer` inputs) as they're bound, so later updates can't change them before the GPU
/// runs: a processor updated more often than its ring has slots, by an Iterator for instance,
/// would otherwise rewrite the bytes earlier dispatches in the same command buffer still read.
///
/// Up to 4 KB go through `setBytes`, which Metal copies at once. Larger inputs are copied into
/// arena storage held until `commandBuffer` completes. Raw `MTLBuffer` and texture bindings
/// never come through here: their contents are the caller's to keep stable.
final class ComputeInputCopies {
    /// Present only while encoding a command-buffer update. Encoder-only updates use
    /// dedicated retained copies because they have no explicit completion boundary.
    private(set) var commandBuffer: MTLCommandBuffer?

    /// Non-escaping scope; nested updates restore their caller's lifetime context.
    @inline(__always)
    func withCommandBuffer(_ commandBuffer: MTLCommandBuffer?, _ body: () throws -> Void) rethrows {
        let previous = self.commandBuffer
        self.commandBuffer = commandBuffer
        defer { self.commandBuffer = previous }
        try body()
    }

    private let arena: FrameArena

    init(device: MTLDevice, label: String) {
        // Each large input takes one slice of its own lease; growing chunks wouldn't pack more.
        arena = FrameArena(device: device, initialChunkLength: 4096, maximumChunkLength: 4096, label: label)
    }

    func bind(_ uniforms: UniformBuffer, at index: ComputeBufferIndex, encoder: MTLComputeCommandEncoder, readOnly: Bool) throws {
        guard readOnly else {
            encoder.setBuffer(uniforms.buffer, offset: uniforms.offset, index: index.rawValue)
            return
        }
        try bind(uniforms.buffer, offset: uniforms.offset, length: uniforms.parameters.size, at: index, encoder: encoder)
    }

    func bind(_ input: BindableBuffer, at index: ComputeBufferIndex, encoder: MTLComputeCommandEncoder, readOnly: Bool) throws {
        guard readOnly else {
            encoder.setBuffer(input.buffer, offset: input.offset, index: index.rawValue)
            return
        }
        try bind(input.buffer, offset: input.offset, length: input.contentLength, at: index, encoder: encoder)
    }

    private func bind(_ buffer: MTLBuffer, offset: Int, length: Int, at index: ComputeBufferIndex, encoder: MTLComputeCommandEncoder) throws {
        precondition(offset >= 0 && offset <= buffer.length && length >= 0 && length <= buffer.length - offset,
                     "The uploaded compute input must fit inside its source buffer")
        // Before its first upload a buffer has no bytes to copy; keep binding it as it is.
        guard length > 0 else {
            encoder.setBuffer(buffer, offset: offset, index: index.rawValue)
            return
        }
        precondition(buffer.storageMode != .private && buffer.storageMode != .memoryless,
                     "Managed compute inputs must be CPU-readable; bind GPU-only resources as raw MTLBuffers")
        let source = buffer.contents().advanced(by: offset)
        if length <= 4096 {
            encoder.setBytes(source, length: length, index: index.rawValue)
        } else if let commandBuffer {
            // FrameTime.zero only labels the lease; the command buffer decides its lifetime.
            let lease = arena.lease(frame: .zero)
            let slice = try lease.allocate(length: length)
            slice.contents.copyMemory(from: source, byteCount: length)
            encoder.setBuffer(slice.buffer, offset: slice.offset, index: index.rawValue)
            lease.retain(untilCompleted: commandBuffer)
            lease.finishRecording()
        } else {
            // With only an encoder there is no completion boundary for arena reuse. A dedicated
            // copy follows Metal's normal retained-resource lifetime instead. Unretained command
            // buffers must use the command-buffer overload, which supplies explicit ownership.
            guard let copy = buffer.device.makeBuffer(bytes: source, length: length, options: .storageModeShared) else {
                throw GPUError.allocationFailed
            }
            encoder.setBuffer(copy, offset: 0, index: index.rawValue)
        }
    }
}
