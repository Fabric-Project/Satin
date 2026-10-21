import Metal

/// An immediate or recorded compute command destination. Binding hooks run on the producer;
/// values written to computeEncoder are captured before an invocation can move to a worker.
public struct ComputeEncodingContext {
    public let computeEncoder: ComputeCommandEncoder

    /// computeEncoder must belong to commandBuffer. The caller ends the Metal encoder.
    public init(commandBuffer: MTLCommandBuffer, computeEncoder: MTLComputeCommandEncoder) {
        precondition(commandBuffer.device === computeEncoder.device, "Compute encoder and command buffer must use the same device")
        self.computeEncoder = ComputeCommandEncoder(commandBuffer: commandBuffer, encoder: computeEncoder)
    }

    init(recorder: ComputePassRecorder) {
        computeEncoder = ComputeCommandEncoder(recorder: recorder)
    }
}
