import Metal
import simd

/// Producer-only recording. GPU preparation is separate: callers using custom encode(in:) hooks
/// must schedule that work before recording the draws which read it. The immediate draw API does
/// this automatically. Sealing consumes the builder; retained aliases cannot record again.
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

    /// Captures the scene and its complete pass plan now. GPU preparation is scheduled
    /// separately; seal() only transfers this already-recorded work.
    public func record(scene: Object, renderPassDescriptor: MTLRenderPassDescriptor,
                       viewMappings: [MTLVertexAmplificationViewMapping] = []) throws {
        try record(scene: scene, renderPassDescriptor: renderPassDescriptor, viewMappings: viewMappings, preparationCommandBuffer: nil)
    }

    func record(scene: Object, renderPassDescriptor: MTLRenderPassDescriptor,
                viewMappings: [MTLVertexAmplificationViewMapping], preparationCommandBuffer: MTLCommandBuffer?) throws {
        guard !isConsumed, recordedPasses == nil else { throw RenderSubmission.Error.alreadyDrawn }
        recordedPasses = try encoder.prepare(builder: self, renderPassDescriptor: renderPassDescriptor, scene: scene,
                                            viewMappings: viewMappings, preparationCommandBuffer: preparationCommandBuffer)
    }

    /// Legacy submission records are colour-only additions to the primary scene's passes.
    func recordAdditional(scene: Object) throws {
        guard !isConsumed, recordedPasses == nil else { throw RenderSubmission.Error.alreadyDrawn }
        encoder.record(scene: scene, into: self)
    }

    public func retainUntilCompleted(_ owner: AnyObject) {
        precondition(!isConsumed, "The builder has been sealed")
        lease.retain(owner)
    }

    public func seal() throws -> SealedSubmission {
        guard !isConsumed else { throw RenderSubmission.Error.alreadyDrawn }
        guard let passes = recordedPasses else { throw RenderSubmission.Error.notRecorded }
        isConsumed = true
        recordedPasses = nil
        return SealedSubmission(builder: self, passes: passes)
    }

}

/// Immutable recorded work. Resource contents follow the versioning/copyOnRecord contract; custom
/// commands must capture stable values. No scene, camera or RenderEncoder is consulted by encode.
public final class SealedSubmission {
    public let frame: FrameTime
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

    public func encode(into commandBuffer: MTLCommandBuffer) throws {
        try lock.sync {
            guard !encoded else { throw RenderSubmission.Error.alreadyDrawn }
            encoded = true
        }
        lease.retain(untilCompleted: commandBuffer)
        lease.finishRecording()
        let storage = recorder.storage
        let pool = pool
        commandBuffer.addCompletedHandler { _ in pool.returnStorage(storage) }
        let state = RenderEncoderState()
        for pass in passes { pass.encode(into: commandBuffer, recorder: recorder, state: state) }
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
    var shadowCompletion: ShadowUpdateCompletion?

    init(descriptor: MTLRenderPassDescriptor, label: String, viewports: [MTLViewport],
         amplificationCount: Int = 1, viewMappings: [MTLVertexAmplificationViewMapping] = [],
         bindings: RenderPassBindings = RenderPassBindings()) {
        self.descriptor = descriptor.copy() as! MTLRenderPassDescriptor
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
        state.begin(renderEncoder: encoder, renderPassDescriptor: descriptor)
        if !viewports.isEmpty { state.setPassViewports(viewports) }
        if amplificationCount > 1 { state.setPassVertexAmplification(count: amplificationCount, viewMappings: viewMappings) }
        bindings.apply(to: state)
        for command in commands {
            switch command {
                case let .indices(indices, viewIndex):
                    recorder.encode(indices, into: state, viewIndex: viewIndex)
                case let .range(range, viewIndex): recorder.encode(range, into: state, viewIndex: viewIndex)
                case let .tileClear(pipeline, size):
                    state.beginInternalDraw()
                    state.pipeline = pipeline
                    encoder.dispatchThreadsPerTile(size)
                case let .tileBlend(pipeline, depth):
                    state.beginInternalDraw()
                    state.pipeline = pipeline
                    state.depthStencilState = depth
                    state.cullMode = MTLCullMode.none
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }
        encoder.endEncoding()
        state.end()
        if let shadowCompletion {
            commandBuffer.addCompletedHandler { completed in shadowCompletion.complete(succeeded: completed.status == .completed) }
        }
    }
}
