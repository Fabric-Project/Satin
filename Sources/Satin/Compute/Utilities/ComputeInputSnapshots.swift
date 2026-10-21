import Metal

/// One producer's CPU input copies. Raw buffers and textures never pass through this helper:
/// their GPU-visible contents can be inputs or outputs and follow the caller's lifetime contract.
struct ComputeInputSnapshots {
    private let arena: FrameArena

    init(device: MTLDevice, label: String) {
        // Each large binding uses one slice in its lease. Growing chunks geometrically would
        // waste memory without packing additional inputs into those chunks.
        self.init(arena: FrameArena(device: device, initialChunkLength: 4096, maximumChunkLength: 4096, label: label))
    }

    init(arena: FrameArena) {
        self.arena = arena
    }

    func bind(_ uniforms: UniformBuffer, at index: ComputeBufferIndex, in context: ComputeEncodingContext) {
        bind(uniforms.buffer, offset: uniforms.offset, length: uniforms.parameters.size, at: index, in: context)
    }

    func bind(_ input: BindableBuffer, at index: ComputeBufferIndex, in context: ComputeEncodingContext) {
        bind(input.buffer, offset: input.offset, length: input.contentLength, at: index, in: context)
    }

    private func bind(_ buffer: MTLBuffer, offset: Int, length: Int, at index: ComputeBufferIndex, in context: ComputeEncodingContext) {
        precondition(offset >= 0 && offset <= buffer.length && length >= 0 && length <= buffer.length - offset,
                     "The uploaded compute input must fit inside its source buffer")
        let encoder = context.computeEncoder
        // Before a BindableBuffer's first upload there are no valid bytes to snapshot. Preserve
        // its existing placeholder binding; reading unuploaded contents remains undefined.
        guard length > 0 else {
            encoder.setBuffer(buffer, offset: offset, index: index.rawValue)
            return
        }
        precondition(buffer.storageMode != .private && buffer.storageMode != .memoryless,
                     "Managed compute inputs must be CPU-readable; bind GPU-only resources as raw MTLBuffers")
        let source = buffer.contents().advanced(by: offset)
        if length <= 4096 {
            encoder.setBytes(source, length: length, index: index.rawValue)
        } else {
            // Compute storage has no motion/frame sampling point. FrameTime.zero labels only
            // this allocation lease; the supplied command buffer defines its actual lifetime.
            let lease = arena.lease(frame: .zero)
            let slice = lease.allocate(length: length)
            slice.contents.copyMemory(from: source, byteCount: length)
            encoder.setBuffer(slice.buffer, offset: slice.offset, index: index.rawValue)
            encoder.retain(lease)
        }
    }
}
