/// A recoverable failure to allocate GPU storage or submit GPU work.
public enum GPUError: Error, Equatable {
    case allocationFailed
    case commandQueueCreationFailed
    case commandBufferCreationFailed
    /// The command buffer failed without supplying a more specific Metal error.
    case commandExecutionFailed
}
