import Metal

/// Custom compute work recorded into a compute pass, between its bindings and dispatches: the compute
/// counterpart of `RecordedGPUWork`, with the same contract (values and Metal resources only, encoded
/// once in order, released after completion).
public protocol RecordedComputeWork {
    func encode(into computeEncoder: MTLComputeCommandEncoder)
}

/// Compute binding/dispatch commands resolved on the producer. The same calls either encode now
/// or capture values for replay; callbacks never need to read their processor on the worker.
public struct ComputeCommandEncoder {
    enum Command {
        case pipeline(MTLComputePipelineState)
        case buffer(MTLBuffer?, offset: Int, index: Int)
        case bytes([UInt8], index: Int)
        case texture(MTLTexture?, index: Int)
        case sampler(MTLSamplerState?, index: Int)
        case threads(MTLSize, group: MTLSize)
        case groups(MTLSize, group: MTLSize)
        case work(any RecordedComputeWork)
        case lease(FrameArena.Lease)

        func encode(into encoder: MTLComputeCommandEncoder, commandBuffer: MTLCommandBuffer) {
            switch self {
                case let .pipeline(pipeline): encoder.setComputePipelineState(pipeline)
                case let .buffer(buffer, offset, index): encoder.setBuffer(buffer, offset: offset, index: index)
                case let .bytes(bytes, index):
                    bytes.withUnsafeBytes { data in
                        if let source = data.baseAddress { encoder.setBytes(source, length: data.count, index: index) }
                    }
                case let .texture(texture, index): encoder.setTexture(texture, index: index)
                case let .sampler(sampler, index): encoder.setSamplerState(sampler, index: index)
                case let .threads(size, group): encoder.dispatchThreads(size, threadsPerThreadgroup: group)
                case let .groups(size, group): encoder.dispatchThreadgroups(size, threadsPerThreadgroup: group)
                case let .work(work): work.encode(into: encoder)
                case let .lease(lease):
                    lease.retain(untilCompleted: commandBuffer)
                    lease.finishRecording()
            }
        }
    }

    private enum Destination {
        case immediate(MTLCommandBuffer, MTLComputeCommandEncoder)
        case recording(ComputePassRecorder)
    }
    private let destination: Destination
    public let device: MTLDevice

    init(commandBuffer: MTLCommandBuffer, encoder: MTLComputeCommandEncoder) {
        device = commandBuffer.device
        destination = .immediate(commandBuffer, encoder)
    }

    init(recorder: ComputePassRecorder) {
        device = recorder.device
        destination = .recording(recorder)
    }

    public var label: String? {
        get {
            switch destination {
                case let .immediate(_, encoder): return encoder.label
                case let .recording(recorder): return recorder.label
            }
        }
        nonmutating set {
            switch destination {
                case let .immediate(_, encoder): encoder.label = newValue
                case let .recording(recorder): recorder.label = newValue
            }
        }
    }

    private func append(_ command: Command) {
        switch destination {
            case let .immediate(buffer, encoder): command.encode(into: encoder, commandBuffer: buffer)
            case let .recording(recorder): recorder.append(command)
        }
    }

    public func setComputePipelineState(_ pipeline: MTLComputePipelineState) { append(.pipeline(pipeline)) }
    public func setBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int) { append(.buffer(buffer, offset: offset, index: index)) }
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {
        precondition(length >= 0 && length <= 4096, "setBytes accepts at most 4096 bytes; use a copied buffer for larger inputs")
        // Immediate calls avoid allocating an intermediate byte array.
        if case let .immediate(_, encoder) = destination { encoder.setBytes(bytes, length: length, index: index) }
        else { append(.bytes(Array(UnsafeRawBufferPointer(start: bytes, count: length)), index: index)) }
    }
    public func setTexture(_ texture: MTLTexture?, index: Int) { append(.texture(texture, index: index)) }
    public func setSamplerState(_ sampler: MTLSamplerState?, index: Int) { append(.sampler(sampler, index: index)) }
    public func dispatchThreads(_ size: MTLSize, threadsPerThreadgroup group: MTLSize) { append(.threads(size, group: group)) }
    public func dispatchThreadgroups(_ size: MTLSize, threadsPerThreadgroup group: MTLSize) { append(.groups(size, group: group)) }

    /// Records custom compute work in order with this pass's bindings and dispatches. See
    /// `RecordedComputeWork`.
    public func append(_ work: some RecordedComputeWork) { append(.work(work)) }
    func retain(_ lease: FrameArena.Lease) { append(.lease(lease)) }
}

/// Producer-only builder. Sealing makes a value copy and closes the mutable command destination.
final class ComputePassRecorder {
    let device: MTLDevice
    var label: String?
    private var commands: [ComputeCommandEncoder.Command] = []
    private var sealed = false

    init(device: MTLDevice) { self.device = device }
    func append(_ command: ComputeCommandEncoder.Command) {
        precondition(!sealed, "A recorded compute context cannot be reused after its pass is sealed")
        commands.append(command)
    }
    func seal() -> RecordedComputePass {
        precondition(!sealed)
        sealed = true
        let pass = RecordedComputePass(label: label, commands: commands)
        commands.removeAll(keepingCapacity: false)
        return pass
    }
}

struct RecordedComputePass {
    let label: String?
    let commands: [ComputeCommandEncoder.Command]

    func encode(into commandBuffer: MTLCommandBuffer) {
        guard !commands.isEmpty, let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = label
        for command in commands { command.encode(into: encoder, commandBuffer: commandBuffer) }
        encoder.endEncoding()
        // The enclosing RecordedGPUCommands holds these bindings through GPU completion,
        // including on unretained command buffers.
    }
}
