import Metal

/// Custom GPU work recorded into an operation, for plugins, nodes and anything Satin doesn't
/// encode itself: blits, MPS kernels, custom passes.
///
/// The contract:
/// - **Values and Metal resources only.** A conforming value never reads or mutates a producer-owned
///   object (scene, material, encoder, node) once recorded. Copy what it needs, such as an MPS kernel's
///   configuration, into its stored properties.
/// - **Encoded exactly once,** in recording order with the operation's render and compute work: at
///   once into the caller's buffer when the encoder has no `renderQueue`, otherwise on that queue.
/// - **Released after its command buffer completes,** possibly on Metal's completion thread. Nothing it
///   holds may have a `deinit` that touches producer state.
/// - **Resource contents aren't frozen** by holding a resource; see `holdUntilCompleted(_:)`.
public protocol RecordedGPUWork {
    func encode(into commandBuffer: MTLCommandBuffer)
}

/// One producer's ordered GPU work. Render packets, compute inputs and pass descriptors are
/// captured now; no live effect, scene or processor is consulted when the recording encodes.
/// Private children append to this same destination instead of scheduling independently.
public final class GPUCommandRecording {
    enum Command {
        case render(SealedSubmission)
        case compute(RecordedComputePass)
        case clear(MTLRenderPassDescriptor, String?)
        case work(any RecordedGPUWork)
        /// Held by the recording until its command buffer completes; encodes nothing.
        case hold(AnyObject)

        func encode(into commandBuffer: MTLCommandBuffer) throws {
            switch self {
                case let .render(submission): try submission.encode(into: commandBuffer)
                case let .compute(pass): pass.encode(into: commandBuffer)
                case let .clear(descriptor, label):
                    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
                    encoder?.label = label
                    encoder?.endEncoding()
                case let .work(work): work.encode(into: commandBuffer)
                case .hold: break
            }
        }
    }

    public let device: MTLDevice
    private let immediateBuffer: MTLCommandBuffer?
    private var commands: [Command] = []
    private var consumed = false

    public init(device: MTLDevice) {
        self.device = device
        immediateBuffer = nil
    }

    init(commandBuffer: MTLCommandBuffer) {
        device = commandBuffer.device
        immediateBuffer = commandBuffer
    }

    private func checkRecording() { precondition(!consumed, "A GPU recording cannot be changed after sealing") }

    func append(_ submission: SealedSubmission) throws {
        checkRecording()
        if let immediateBuffer {
            RecordingProfile.begin(.producerReplay)
            defer { RecordingProfile.end() }
            try submission.encode(into: immediateBuffer)
        }
        else { commands.append(.render(submission)) }
    }

    /// Capture a whole compute pass. The body and processor extension hooks run on the producer;
    /// the resulting Metal binding and dispatch calls run only when the recording is encoded.
    public func compute(label: String? = nil, _ body: (ComputeEncodingContext) -> Void) {
        checkRecording()
        if let immediateBuffer {
            guard let encoder = immediateBuffer.makeComputeCommandEncoder() else { return }
            encoder.label = label
            body(ComputeEncodingContext(commandBuffer: immediateBuffer, computeEncoder: encoder))
            encoder.endEncoding()
        } else {
            let recorder = ComputePassRecorder(device: device)
            recorder.label = label
            body(ComputeEncodingContext(recorder: recorder))
            commands.append(.compute(recorder.seal()))
        }
    }

    public func compute(_ processor: ComputeProcessor, iterations: Int = 1) {
        precondition(device === processor.device)
        processor.update(self, iterations: iterations)
    }

    public func compute(_ system: ComputeSystem, iterations: Int = 1) {
        precondition(device === system.device)
        system.update(self, iterations: iterations)
    }

    /// Compose a scene inside this operation's ordering boundary, including its GPU preparation.
    public func draw(_ renderer: RenderEncoder, frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor,
                     scene: Object, cameras: [Camera], viewports: [MTLViewport],
                     viewMappings: [MTLVertexAmplificationViewMapping] = []) throws {
        checkRecording()
        precondition(device === renderer.context.device)
        let builder = renderer.makeSubmissionBuilder(frame: frame, cameras: cameras, viewports: viewports)
        try builder.record(scene: scene, renderPassDescriptor: renderPassDescriptor,
                           viewMappings: viewMappings, preparationCommands: self)
        let sealed = try builder.seal()
        try append(sealed)
    }

    /// Record one private child into this operation, without taking a permit or consulting its queue.
    public func draw(_ effect: PostProcessEncoder, frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor,
                     viewports: [MTLViewport] = [], viewMappings: [MTLVertexAmplificationViewMapping] = [],
                     renderTarget: MTLTexture? = nil) throws {
        checkRecording()
        precondition(device === effect.context.device)
        let descriptor = renderTarget.map { renderPassDescriptor.targeting($0, sampleCount: effect.context.sampleCount) } ?? renderPassDescriptor
        try effect.encodeEffect(frame: frame, renderPassDescriptor: descriptor, commands: self,
                                viewports: viewports, viewMappings: viewMappings)
    }

    /// A pass with no draws, such as initializing fallback depth. The descriptor is copied now.
    public func clear(_ descriptor: MTLRenderPassDescriptor, label: String? = nil) {
        checkRecording()
        if let immediateBuffer {
            let encoder = immediateBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            encoder?.label = label
            encoder?.endEncoding()
        } else { commands.append(.clear(descriptor.privateCopy(), label)) }
    }

    /// Records custom GPU work in order with the operation's other work. See `RecordedGPUWork`.
    public func append(_ work: some RecordedGPUWork) {
        checkRecording()
        if let immediateBuffer {
            work.encode(into: immediateBuffer)
            immediateBuffer.addCompletedHandler { _ in withExtendedLifetime(work) {} }
        } else { commands.append(.work(work)) }
    }

    /// Keeps an external resource's owner alive until this operation's GPU work completes.
    ///
    /// For resources whose validity or contents depend on an object outside Satin:
    /// - object lifetime: a `CVMetalTexture`'s texture is invalid once the wrapper is released;
    /// - content lifetime: a pooled `CVPixelBuffer` or `IOSurface` is recycled, and overwritten by a
    ///   later frame, once its owner lets it go.
    ///
    /// Released at command-buffer completion, possibly on Metal's completion thread: hold only owners
    /// whose `deinit` is safe there (CoreVideo and IOSurface types are; scene objects aren't). A
    /// consumed recording releases its holds at completion even if the caller keeps the recording.
    public func holdUntilCompleted(_ owner: AnyObject) {
        checkRecording()
        if let immediateBuffer {
            immediateBuffer.addCompletedHandler { _ in withExtendedLifetime(owner) {} }
        } else { commands.append(.hold(owner)) }
    }

    public func seal() -> RecordedGPUCommands {
        checkRecording()
        precondition(immediateBuffer == nil, "Immediate GPU commands are already encoded")
        consumed = true
        let recorded = RecordedGPUCommands(commands: commands)
        commands.removeAll(keepingCapacity: false)
        return recorded
    }
}

/// A single-use, self-contained operation. Keeping a consumed producer recorder does not retain
/// its contents. Abandonment releases snapshots without reserving any GPU queue position.
public final class RecordedGPUCommands {
    private var commands: [GPUCommandRecording.Command]?
    private let lock = UnfairLock()

    init(commands: [GPUCommandRecording.Command]) { self.commands = commands }

    public func encode(into commandBuffer: MTLCommandBuffer) throws {
        let commands: [GPUCommandRecording.Command] = try lock.sync {
            guard let commands = self.commands else { throw SubmissionError.alreadyDrawn }
            self.commands = nil
            return commands
        }
        commandBuffer.addCompletedHandler { [commands] _ in withExtendedLifetime(commands) {} }
        for command in commands { try command.encode(into: commandBuffer) }
    }
}
