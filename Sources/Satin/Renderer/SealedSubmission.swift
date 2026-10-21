import Metal
import simd

/// One rendering operation of one `RenderEncoder`, recorded on the producer: a frame and the views
/// it draws from, fixed when the builder is made, before anything is updated or recorded.
///
/// `record(scene:)` captures a scene as it is at that moment (its objects' transforms, materials'
/// uniforms, instances and poses, snapshotted into the frame arena), so changing the scene afterwards,
/// as an Iterator does between iterations, doesn't alter what was recorded. Those records draw in
/// the colour passes only, as they never cast shadows. `record(scene:renderPassDescriptor:)` then
/// updates and records the operation's own scene and plans every pass: per render layer, its own
/// draws, then each record in call order. `seal()` hands that work over without sampling the scene
/// again.
///
/// The encoder's settings (rendering mode, outputs, sorting, clear and load/store actions) are
/// frozen when the builder is made, and so is its destination: the encoder's pixel formats. A
/// record rejected before doing any work (a descriptor not matching the destination) leaves the
/// builder usable. One released without sealing gives its storage back.
public final class SubmissionBuilder {
    let encoder: RenderEncoder
    let recorder: PacketRecorder
    let lease: FrameArena.Lease
    let frame: FrameTime
    let destination: RenderDestination
    let configuration: SubmissionConfiguration
    let cameras: [Camera]
    let viewports: [MTLViewport]
    let simdViewports: [simd_float4]
    let views: [RenderView]
    let pool: PacketStoragePool
    private(set) var isConsumed = false
    private var recordedPasses: [RecordedRenderPass]?

    init(encoder: RenderEncoder, recorder: PacketRecorder, lease: FrameArena.Lease, frame: FrameTime,
         destination: RenderDestination, configuration: SubmissionConfiguration, cameras: [Camera],
         viewports: [MTLViewport], pool: PacketStoragePool) {
        self.encoder = encoder
        self.recorder = recorder
        self.lease = lease
        self.frame = frame
        self.destination = destination
        self.configuration = configuration
        self.cameras = cameras
        self.viewports = viewports
        self.pool = pool
        simdViewports = viewports.map(\.float4)
        views = cameras.enumerated().map { index, camera in
            RenderView(camera: camera, viewport: viewports.isEmpty ? .zero : viewports[min(index, viewports.count - 1)].float4, frame: frame)
        }
    }

    deinit {
        if !isConsumed { pool.returnStorage(recorder.storage) }
    }

    /// Records `scene` as it is now, drawn in this operation's colour passes after its own scene.
    /// Neither updates nor encodes it: do both first. Call before `record(scene:renderPassDescriptor:)`.
    public func record(scene: Object) throws {
        guard !isConsumed, recordedPasses == nil else { throw SubmissionError.alreadyDrawn }
        encoder.record(scene: scene, into: self)
    }

    /// Updates and records the scene and its complete pass plan now. preparationCommands captures
    /// GPU preparation hooks before the scene's passes. preparationCommandBuffer is the immediate
    /// compatibility path; do not supply both. Without either, schedule preparation separately.
    public func record(scene: Object, renderPassDescriptor: MTLRenderPassDescriptor,
                       viewMappings: [MTLVertexAmplificationViewMapping] = [], preparationCommandBuffer: MTLCommandBuffer? = nil,
                       preparationCommands: GPUCommandRecording? = nil) throws {
        guard !isConsumed, recordedPasses == nil else { throw SubmissionError.alreadyDrawn }
        precondition(preparationCommandBuffer == nil || preparationCommands == nil, "Choose one preparation command destination")
        recordedPasses = try encoder.prepare(builder: self, renderPassDescriptor: renderPassDescriptor, scene: scene,
                                            viewMappings: viewMappings, preparationCommandBuffer: preparationCommandBuffer, preparationCommands: preparationCommands)
    }

    /// For GPU preparation (`encode(in:)`) of what this operation records, into `commandBuffer`.
    public func encodingContext(commandBuffer: MTLCommandBuffer) -> EncodingContext {
        EncodingContext(commandBuffer: commandBuffer, frame: frame, views: views, recorder: recorder)
    }

    /// GPU preparation into an ordered recording, without encoding on the producer.
    public func encodingContext(commands: GPUCommandRecording) -> EncodingContext {
        EncodingContext(commands: commands, frame: frame, views: views, recorder: recorder)
    }

    public func seal() throws -> SealedSubmission {
        guard !isConsumed else { throw SubmissionError.alreadyDrawn }
        guard let passes = recordedPasses else { throw SubmissionError.notRecorded }
        isConsumed = true
        recordedPasses = nil
        return SealedSubmission(builder: self, passes: passes)
    }

}

/// Immutable recorded work, self-contained: values, frame-arena slices and Metal resources only.
/// Resource contents follow the versioning/copyOnRecordLength contract. No scene, camera or
/// RenderEncoder is consulted by encode, and completion never reaches back into one.
public final class SealedSubmission {
    public let frame: FrameTime
    /// Identifies the recording to its producer, for `RenderEncoder.abandon(_:)`.
    let recordToken: UInt64
    private let passes: [RecordedRenderPass]
    private let recorder: PacketRecorder
    private let lease: FrameArena.Lease
    private let pool: PacketStoragePool
    private let lock = UnfairLock()
    private var encoded = false

    convenience init(builder: SubmissionBuilder, passes: [RecordedRenderPass]) {
        self.init(frame: builder.frame, recorder: builder.recorder, lease: builder.lease, pool: builder.pool, passes: passes)
    }

    init(frame: FrameTime, recorder: PacketRecorder, lease: FrameArena.Lease, pool: PacketStoragePool, passes: [RecordedRenderPass]) {
        recordToken = recorder.storage.leaseToken
        self.frame = frame
        self.recorder = recorder
        self.lease = lease
        self.pool = pool
        self.passes = passes
    }

    deinit {
        if !encoded {
            lease.finishRecording()
            pool.returnStorage(recorder.storage)
        }
    }

    /// Gives the recording up unencoded, releasing what it holds; encoding it afterwards throws.
    /// Returns false when it was already encoded or discarded.
    @discardableResult
    func discard() -> Bool {
        let wasPending: Bool = lock.sync {
            guard !encoded else { return false }
            encoded = true
            return true
        }
        guard wasPending else { return false }
        lease.finishRecording()
        pool.returnStorage(recorder.storage)
        return true
    }

    public func encode(into commandBuffer: MTLCommandBuffer) throws {
        try lock.sync {
            guard !encoded else { throw SubmissionError.alreadyDrawn }
            encoded = true
        }
        lease.retain(untilCompleted: commandBuffer)
        lease.finishRecording()
        let storage = recorder.storage
        let pool = pool
        commandBuffer.addCompletedHandler { _ in pool.returnStorage(storage) }
        for pass in passes { pass.encode(into: commandBuffer, recorder: recorder, state: storage.encoderState) }
    }
}

/// One complete pass; descriptors are private copies captured while preparing the submission.
struct RecordedRenderPass {
    enum Command {
        case indices(ArraySlice<Int>, viewIndex: Int)
        case range(Range<Int>, viewIndex: Int)
        case tileClear(MTLRenderPipelineState, MTLSize)
        case tileBlend(MTLRenderPipelineState, MTLDepthStencilState)
    }
    let descriptor: MTLRenderPassDescriptor
    let label: String
    let viewports: [MTLViewport]
    let amplificationCount: Int
    let viewMappings: [MTLVertexAmplificationViewMapping]
    let bindings: RenderPassBindings
    var commands: [Command] = []

    init(descriptor: MTLRenderPassDescriptor, label: String, viewports: [MTLViewport],
         amplificationCount: Int = 1, viewMappings: [MTLVertexAmplificationViewMapping] = [],
         bindings: RenderPassBindings = RenderPassBindings()) {
        self.descriptor = descriptor.privateCopy()
        self.label = label
        self.viewports = viewports
        self.amplificationCount = amplificationCount
        self.viewMappings = viewMappings.isEmpty && amplificationCount > 1
            ? (0 ..< amplificationCount).map { .init(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0)) }
            : viewMappings
        self.bindings = bindings
    }

    func encode(into commandBuffer: MTLCommandBuffer, recorder: PacketRecorder, state: RenderEncoderState) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = label
        state.begin(renderEncoder: encoder)
        if !viewports.isEmpty { state.setPassViewports(viewports) }
        if amplificationCount > 1 { state.setPassVertexAmplification(count: amplificationCount, viewMappings: viewMappings) }
        bindings.apply(to: state)
        for command in commands {
            switch command {
                case let .indices(indices, viewIndex):
                    recorder.encode(indices, into: state, viewIndex: viewIndex)
                case let .range(range, viewIndex): recorder.encode(range, into: state, viewIndex: viewIndex)
                case let .tileClear(pipeline, size):
                    state.pipeline = pipeline
                    encoder.dispatchThreadsPerTile(size)
                case let .tileBlend(pipeline, depth):
                    state.pipeline = pipeline
                    state.depthStencilState = depth
                    state.cullMode = MTLCullMode.none
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }
        encoder.endEncoding()
        state.end()
    }
}

extension MTLRenderPassDescriptor {
    /// Redirect attachment zero without mutating the caller's descriptor.
    func targeting(_ texture: MTLTexture, sampleCount: Int) -> MTLRenderPassDescriptor {
        let descriptor = privateCopy()
        if sampleCount > 1 { descriptor.colorAttachments[0].resolveTexture = texture }
        else { descriptor.colorAttachments[0].texture = texture }
        return descriptor
    }

    func colorTarget(sampleCount: Int) -> MTLTexture? {
        sampleCount > 1 ? colorAttachments[0].resolveTexture : colorAttachments[0].texture
    }

    /// A copy the caller can't change afterwards. `copy()` of a render pass descriptor is always one.
    func privateCopy() -> MTLRenderPassDescriptor {
        guard let copy = copy() as? MTLRenderPassDescriptor else {
            preconditionFailure("MTLRenderPassDescriptor.copy() returned another type")
        }
        return copy
    }
}
