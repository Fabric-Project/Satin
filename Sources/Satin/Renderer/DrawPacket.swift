//
//  DrawPacket.swift
//  Satin
//

import Metal

// MARK: - Packets

/// One draw call, recorded: the state it needs, the range of commands that bind its resources, and
/// the call itself. Plain data: references are indices into its `PacketStorage`'s reference arrays,
/// so storing and clearing packets does no reference counting.
struct DrawPacket {
    var pipelineIndex: Int32
    /// Into `PacketStorage.depthStencilStates`; -1 when the draw sets no depth state.
    var depthStencilStateIndex: Int32
    var setsDepthState: Bool
    var depthBias: DepthBias?
    var depthClipMode: MTLDepthClipMode?
    var cullMode: MTLCullMode
    var windingOrder: MTLWinding
    var triangleFillMode: MTLTriangleFillMode
    var renderOrder: Int
    var commandStart: Int32
    var commandCount: Int32
    var drawCall: PacketDrawCall
    /// Into `PacketStorage.debugLabels` in debug builds; -1 otherwise.
    var debugLabelIndex: Int32
}

/// A packet's draw call. `custom` means one of its custom commands issued the draw.
enum PacketDrawCall {
    case primitives(MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
    case indexedPrimitives(MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBufferIndex: Int32, indexBufferOffset: Int, instanceCount: Int)
    case custom
}

/// One recorded command, in the order it was recorded. References are indices into the storage's
/// arrays; a texture index of -1 binds nil.
enum PacketCommand {
    case vertexBuffer(bufferIndex: Int32, offset: Int, slot: VertexBufferIndex)
    case fragmentBuffer(bufferIndex: Int32, offset: Int, slot: FragmentBufferIndex)
    case vertexTexture(textureIndex: Int32, slot: VertexTextureIndex)
    case fragmentTexture(textureIndex: Int32, slot: FragmentTextureIndex)
    case fragmentPBRTexture(textureIndex: Int32, type: PBRTextureType)
    case fragmentSampler(samplerIndex: Int32, slot: FragmentSamplerIndex)
    case custom(commandIndex: Int32)
}

// MARK: - Storage

/// The packets one draw records, with every object they reference held strongly until the draw is
/// encoded. Leased to one draw at a time by a `PacketStoragePool`, and cleared, keeping capacity,
/// when returned.
///
/// Recording: `beginRecording` starts one renderable's recording in one pass; commands recorded
/// before its first material are its shared prefix, copied into every packet it produces (a mesh's
/// geometry bindings into each submesh's packet). Each material starts a packet without a pipeline;
/// a draw call finishes it, or abandons it if no pipeline was set. `endRecording` drops anything
/// recorded after the last draw call.
final class PacketStorage {
    /// Unique across every storage of every encoder, for the life of the process: snapshot caches
    /// (material uniforms, instances, palettes) key on it, so one never reuses another lease's slice.
    fileprivate(set) var leaseToken: UInt64 = 0

    /// One renderable's packets for one route, in the order recorded: a draw's own scene, and each
    /// `record(scene:)` into its submission.
    struct PacketRun {
        let renderLayer: Int
        let routeIndex: Int
        let packets: Range<Int>
        /// From `record(scene:)`, encoded after the draw's own scene in its layer.
        let isRecorded: Bool
    }

    private(set) var runs: [PacketRun] = []

    func appendRun(renderLayer: Int, routeIndex: Int, packets: Range<Int>, isRecorded: Bool) {
        guard !packets.isEmpty else { return }
        runs.append(PacketRun(renderLayer: renderLayer, routeIndex: routeIndex, packets: packets, isRecorded: isRecorded))
    }

    private(set) var packets: [DrawPacket] = []
    private(set) var commands: [PacketCommand] = []
    private(set) var buffers: [MTLBuffer] = []
    private(set) var textures: [MTLTexture] = []
    private(set) var samplers: [MTLSamplerState] = []
    private(set) var pipelines: [MTLRenderPipelineState] = []
    private(set) var depthStencilStates: [MTLDepthStencilState] = []
    private(set) var customCommands: [(MTLRenderCommandEncoder) -> Void] = []
#if DEBUG
    private(set) var debugLabels: [String] = []
#endif

    /// How much of each array a point in recording had used, to roll back to.
    private struct Marks {
        var commands = 0
        var buffers = 0
        var textures = 0
        var samplers = 0
        var pipelines = 0
        var depthStencilStates = 0
        var customCommands = 0
    }

    // The packet being built.
    private var packetCommandStart = 0
    private var ownStart = Marks()
    private var prefixLength: Int?
    private var pendingPipelineIndex: Int32 = -1
    private var pendingDepthStencilStateIndex: Int32 = -1
    private var pendingSetsDepthState = false
    private var pendingDepthBias: DepthBias?
    private var pendingDepthClipMode: MTLDepthClipMode?
    private var recordingCullMode: MTLCullMode = .back
    private var recordingWindingOrder: MTLWinding = .counterClockwise
    private var recordingTriangleFillMode: MTLTriangleFillMode = .fill
    private var recordingRenderOrder = 0
    private var recordingDebugLabelIndex: Int32 = -1

    func reset() {
        runs.removeAll(keepingCapacity: true)
        packets.removeAll(keepingCapacity: true)
        commands.removeAll(keepingCapacity: true)
        buffers.removeAll(keepingCapacity: true)
        textures.removeAll(keepingCapacity: true)
        samplers.removeAll(keepingCapacity: true)
        pipelines.removeAll(keepingCapacity: true)
        depthStencilStates.removeAll(keepingCapacity: true)
        customCommands.removeAll(keepingCapacity: true)
#if DEBUG
        debugLabels.removeAll(keepingCapacity: true)
#endif
    }

    // MARK: Recording

    func beginRecording(cullMode: MTLCullMode, windingOrder: MTLWinding, triangleFillMode: MTLTriangleFillMode, renderOrder: Int, debugLabel: @autoclosure () -> String) {
        recordingCullMode = cullMode
        recordingWindingOrder = windingOrder
        recordingTriangleFillMode = triangleFillMode
        recordingRenderOrder = renderOrder
#if DEBUG
        debugLabels.append(debugLabel())
        recordingDebugLabelIndex = Int32(debugLabels.count - 1)
#endif
        packetCommandStart = commands.count
        prefixLength = nil
        startOwnCommands()
    }

    /// A material is about to record: the packet's own commands start here, without a pipeline.
    func beginMaterial() {
        if prefixLength == nil {
            prefixLength = commands.count - packetCommandStart
        }
        startOwnCommands()
    }

    func endRecording() {
        // Anything recorded after the last draw call draws nothing.
        rollBack(to: Marks(
            commands: packetCommandStart,
            buffers: ownStart.buffers,
            textures: ownStart.textures,
            samplers: ownStart.samplers,
            pipelines: ownStart.pipelines,
            depthStencilStates: ownStart.depthStencilStates,
            customCommands: ownStart.customCommands
        ))
        prefixLength = nil
    }

    private func startOwnCommands() {
        ownStart = Marks(
            commands: commands.count,
            buffers: buffers.count,
            textures: textures.count,
            samplers: samplers.count,
            pipelines: pipelines.count,
            depthStencilStates: depthStencilStates.count,
            customCommands: customCommands.count
        )
        pendingPipelineIndex = -1
        pendingDepthStencilStateIndex = -1
        pendingSetsDepthState = false
        pendingDepthBias = nil
        pendingDepthClipMode = nil
    }

    private func rollBack(to marks: Marks) {
        commands.removeSubrange(marks.commands...)
        buffers.removeSubrange(marks.buffers...)
        textures.removeSubrange(marks.textures...)
        samplers.removeSubrange(marks.samplers...)
        pipelines.removeSubrange(marks.pipelines...)
        depthStencilStates.removeSubrange(marks.depthStencilStates...)
        customCommands.removeSubrange(marks.customCommands...)
    }

    func setPipeline(_ pipeline: MTLRenderPipelineState) {
        pipelines.append(pipeline)
        pendingPipelineIndex = Int32(pipelines.count - 1)
    }

    func setDepthStencilState(_ depthStencilState: MTLDepthStencilState?, bias: DepthBias?, clipMode: MTLDepthClipMode?) {
        if let depthStencilState {
            depthStencilStates.append(depthStencilState)
            pendingDepthStencilStateIndex = Int32(depthStencilStates.count - 1)
        } else {
            pendingDepthStencilStateIndex = -1
        }
        pendingSetsDepthState = true
        pendingDepthBias = bias
        pendingDepthClipMode = clipMode
    }

    func appendVertexBuffer(_ buffer: MTLBuffer, offset: Int, slot: VertexBufferIndex) {
        buffers.append(buffer)
        commands.append(.vertexBuffer(bufferIndex: Int32(buffers.count - 1), offset: offset, slot: slot))
    }

    func appendFragmentBuffer(_ buffer: MTLBuffer, offset: Int, slot: FragmentBufferIndex) {
        buffers.append(buffer)
        commands.append(.fragmentBuffer(bufferIndex: Int32(buffers.count - 1), offset: offset, slot: slot))
    }

    func appendVertexTexture(_ texture: MTLTexture?, slot: VertexTextureIndex) {
        commands.append(.vertexTexture(textureIndex: textureIndex(texture), slot: slot))
    }

    func appendFragmentTexture(_ texture: MTLTexture?, slot: FragmentTextureIndex) {
        commands.append(.fragmentTexture(textureIndex: textureIndex(texture), slot: slot))
    }

    func appendFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        commands.append(.fragmentPBRTexture(textureIndex: textureIndex(texture), type: type))
    }

    func appendFragmentSampler(_ sampler: MTLSamplerState, slot: FragmentSamplerIndex) {
        samplers.append(sampler)
        commands.append(.fragmentSampler(samplerIndex: Int32(samplers.count - 1), slot: slot))
    }

    func appendCustomCommand(_ command: @escaping (MTLRenderCommandEncoder) -> Void) {
        customCommands.append(command)
        commands.append(.custom(commandIndex: Int32(customCommands.count - 1)))
    }

    private func textureIndex(_ texture: MTLTexture?) -> Int32 {
        guard let texture else { return -1 }
        textures.append(texture)
        return Int32(textures.count - 1)
    }

    /// Finishes the packet with `drawCall`, or abandons it when no material set a pipeline. The next
    /// packet of the recording starts with a copy of the shared prefix.
    func finishPacket(drawCall: PacketDrawCall) {
        guard pendingPipelineIndex >= 0 else {
            rollBack(to: ownStart)
            startOwnCommands()
            return
        }

        packets.append(DrawPacket(
            pipelineIndex: pendingPipelineIndex,
            depthStencilStateIndex: pendingDepthStencilStateIndex,
            setsDepthState: pendingSetsDepthState,
            depthBias: pendingDepthBias,
            depthClipMode: pendingDepthClipMode,
            cullMode: recordingCullMode,
            windingOrder: recordingWindingOrder,
            triangleFillMode: recordingTriangleFillMode,
            renderOrder: recordingRenderOrder,
            commandStart: Int32(packetCommandStart),
            commandCount: Int32(commands.count - packetCommandStart),
            drawCall: drawCall,
            debugLabelIndex: recordingDebugLabelIndex
        ))

        let finishedStart = packetCommandStart
        packetCommandStart = commands.count
        for commandIndex in finishedStart ..< finishedStart + (prefixLength ?? 0) {
            commands.append(commands[commandIndex])
        }
        startOwnCommands()
    }

    // MARK: Encoding

    /// Replays `packet` into `state`: its state, its commands in recorded order, then its draw call.
    func encode(_ packet: DrawPacket, into state: RenderEncoderState) {
        let renderEncoder = state.renderEncoder
#if DEBUG
        renderEncoder.pushDebugGroup(debugLabels[Int(packet.debugLabelIndex)])
        defer { renderEncoder.popDebugGroup() }
#endif
        // After a custom command, the pass is put back before this packet sets its own state.
        state.beginPacket()
        state.cullMode = packet.cullMode
        state.windingOrder = packet.windingOrder
        state.triangleFillMode = packet.triangleFillMode
        state.pipeline = pipelines[Int(packet.pipelineIndex)]
        if packet.setsDepthState {
            state.depthStencilState = packet.depthStencilStateIndex >= 0 ? depthStencilStates[Int(packet.depthStencilStateIndex)] : nil
            state.depthBias = packet.depthBias
            state.depthClipMode = packet.depthClipMode
        }

        let commandEnd = Int(packet.commandStart + packet.commandCount)
        for commandIndex in Int(packet.commandStart) ..< commandEnd {
            switch commands[commandIndex] {
            case let .vertexBuffer(bufferIndex, offset, slot):
                state.setVertexBuffer(buffers[Int(bufferIndex)], offset: offset, index: slot)
            case let .fragmentBuffer(bufferIndex, offset, slot):
                state.setFragmentBuffer(buffers[Int(bufferIndex)], offset: offset, index: slot)
            case let .vertexTexture(textureIndex, slot):
                state.setVertexTexture(texture(at: textureIndex), index: slot)
            case let .fragmentTexture(textureIndex, slot):
                state.setFragmentTexture(texture(at: textureIndex), index: slot)
            case let .fragmentPBRTexture(textureIndex, type):
                state.setFragmentPBRTexture(texture(at: textureIndex), type: type)
            case let .fragmentSampler(samplerIndex, slot):
                renderEncoder.setFragmentSamplerState(samplers[Int(samplerIndex)], index: slot.rawValue)
            case let .custom(commandIndex):
                customCommands[Int(commandIndex)](renderEncoder)
                // A custom command may set anything: forget what the encoder is known to hold.
                // What it set holds for the rest of this packet; the next one starts from the pass.
                state.invalidate()
            }
        }

        switch packet.drawCall {
        case let .primitives(type, vertexStart, vertexCount, instanceCount):
            renderEncoder.drawPrimitives(type: type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount)
        case let .indexedPrimitives(type, indexCount, indexType, indexBufferIndex, indexBufferOffset, instanceCount):
            renderEncoder.drawIndexedPrimitives(
                type: type,
                indexCount: indexCount,
                indexType: indexType,
                indexBuffer: buffers[Int(indexBufferIndex)],
                indexBufferOffset: indexBufferOffset,
                instanceCount: instanceCount
            )
        case .custom:
            break
        }
    }

    /// The index buffer of an indexed draw is kept with the other buffers.
    func appendIndexBuffer(_ buffer: MTLBuffer) -> Int32 {
        buffers.append(buffer)
        return Int32(buffers.count - 1)
    }

    private func texture(at index: Int32) -> MTLTexture? {
        index >= 0 ? textures[Int(index)] : nil
    }

    func pipeline(of packet: DrawPacket) -> MTLRenderPipelineState {
        pipelines[Int(packet.pipelineIndex)]
    }
}

// MARK: - Pool

/// Storage for an encoder's draws: each draw leases one storage and returns it once encoded, so
/// two draws in flight never share or clear each other's packets.
final class PacketStoragePool {
    private var available: [PacketStorage] = []

    /// Storages returned and ready to lease.
    var availableCount: Int { available.count }

    private static let leaseTokenLock = UnfairLock()
    private nonisolated(unsafe) static var lastLeaseToken: UInt64 = 0

    func lease() -> PacketStorage {
        let storage = available.popLast() ?? PacketStorage()
        storage.leaseToken = Self.leaseTokenLock.sync {
            Self.lastLeaseToken &+= 1
            return Self.lastLeaseToken
        }
        return storage
    }

    func returnStorage(_ storage: PacketStorage) {
        storage.reset()
        available.append(storage)
    }
}
