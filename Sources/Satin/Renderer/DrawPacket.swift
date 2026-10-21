//
//  DrawPacket.swift
//  Satin
//

import Metal

// MARK: - Packets

/// One draw call, recorded: the state it needs, the range of commands that bind its resources, and
/// the call itself. Plain data: references are indices into its `PacketTables`' reference arrays,
/// so storing and clearing packets does no reference counting.
struct DrawPacket {
    var pipelineIndex: Int32
    /// Into `PacketTables.depthStencilStates`; -1 when the draw sets no depth state.
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
    /// Into `PacketTables.debugLabels` in debug builds; -1 otherwise.
    var debugLabelIndex: Int32
}

/// A packet's draw call, as data: vertices, indices, tessellation patches or mesh-shader threadgroups.
enum PacketDrawCall {
    case primitives(MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
    case indexedPrimitives(MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBufferIndex: Int32, indexBufferOffset: Int, instanceCount: Int)
    case patches(controlPointCount: Int, patchCount: Int, instanceCount: Int)
    /// `controlPointIndexBufferIndex` is into the storage's buffers.
    case indexedPatches(controlPointCount: Int, patchCount: Int, controlPointIndexBufferIndex: Int32, instanceCount: Int)
    case meshThreadgroups(MTLSize, threadsPerObjectThreadgroup: MTLSize, threadsPerMeshThreadgroup: MTLSize)
}

/// One recorded command, in the order it was recorded. References are indices into the storage's
/// arrays; a texture index of -1 binds nil.
///
/// The per-view cases bind the render event's own vertex uniforms: one `VertexUniforms` per view.
/// Encoded for view k, their offset moves on by k of the recorder's captured view stride, so one
/// recording serves each view of a multi-view shadow (a point light's faces) in its own pass.
/// Amplified events are only ever encoded as view 0: their shaders index the views themselves.
enum PacketCommand {
    case vertexBuffer(bufferIndex: Int32, offset: Int, slot: VertexBufferIndex)
    case fragmentBuffer(bufferIndex: Int32, offset: Int, slot: FragmentBufferIndex)
    case perViewVertexBuffer(bufferIndex: Int32, offset: Int, slot: VertexBufferIndex)
    case perViewFragmentBuffer(bufferIndex: Int32, offset: Int, slot: FragmentBufferIndex)
    case vertexTexture(textureIndex: Int32, slot: VertexTextureIndex)
    case fragmentTexture(textureIndex: Int32, slot: FragmentTextureIndex)
    case fragmentPBRTexture(textureIndex: Int32, type: PBRTextureType)
    case fragmentSampler(samplerIndex: Int32, slot: FragmentSamplerIndex)
    // Mesh-shader stages.
    case objectBuffer(bufferIndex: Int32, offset: Int, slot: ObjectBufferIndex)
    case meshBuffer(bufferIndex: Int32, offset: Int, slot: MeshBufferIndex)
    case perViewObjectBuffer(bufferIndex: Int32, offset: Int, slot: ObjectBufferIndex)
    case perViewMeshBuffer(bufferIndex: Int32, offset: Int, slot: MeshBufferIndex)
    case tessellationFactorBuffer(bufferIndex: Int32, offset: Int, instanceStride: Int)
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
///
/// Everything recorded lives in one `PacketTables` value, and each operation is one call on it: one
/// checked access to the storage per operation, however many fields it touches.
final class PacketStorage {
    /// Unique across every storage of every encoder, for the life of the process: snapshot caches
    /// (material uniforms, instances, palettes) key on it, so one never reuses another lease's slice.
    fileprivate(set) var leaseToken: UInt64 = 0

    private(set) var tables = PacketTables()

    /// The encoder state this storage's submission encodes with, reused with the storage so encoding
    /// allocates none. A storage is leased to one submission at a time, which encodes once.
    let encoderState = RenderEncoderState()

    var runs: ContiguousArray<PacketTables.PacketRun> { tables.runs }
    var packets: ContiguousArray<DrawPacket> { tables.packets }
    var packetCount: Int { tables.packets.count }
    var commands: ContiguousArray<PacketCommand> { tables.commands }
    var buffers: ContiguousArray<MTLBuffer> { tables.buffers }

    /// The views this storage's vertex uniforms are written from, as values: each distinct set of
    /// views is appended once and shared by every record of it.
    private(set) var viewTable = ContiguousArray<RenderView>()
    /// Vertex uniforms reserved while recording and written when this storage's submission encodes,
    /// on whichever thread encodes it, so recording on the producer computes no per-view matrices.
    private(set) var vertexUniformsJobs = ContiguousArray<VertexUniformsJob>()

    func reset() {
        tables.reset()
        viewTable.removeAll(keepingCapacity: true)
        vertexUniformsJobs.removeAll(keepingCapacity: true)
    }

    func appendViews(_ views: [RenderView]) -> Range<Int> {
        let start = viewTable.count
        viewTable.append(contentsOf: views)
        return start ..< viewTable.count
    }

    func appendVertexUniformsJob(_ job: VertexUniformsJob) {
        vertexUniformsJobs.append(job)
    }

    /// Whether `range` of `buffer` overlaps a vertex-uniforms slot still waiting to be written.
    func reservesVertexUniforms(in buffer: MTLBuffer, range: Range<Int>) -> Bool {
        for job in vertexUniformsJobs where job.slice.buffer === buffer {
            if job.slice.offset < range.upperBound, range.lowerBound < job.slice.offset + job.slice.length { return true }
        }
        return false
    }

    /// Writes every reserved vertex-uniforms slot, then forgets the jobs: the encode that follows
    /// binds them, and a second fill finds nothing to do.
    func writeVertexUniforms() {
        for job in vertexUniformsJobs { job.write(from: viewTable) }
        vertexUniformsJobs.removeAll(keepingCapacity: true)
    }

    func appendRun(renderLayer: Int, routeIndex: Int, packets: Range<Int>, isRecorded: Bool) {
        tables.appendRun(renderLayer: renderLayer, routeIndex: routeIndex, packets: packets, isRecorded: isRecorded)
    }

    // MARK: Recording

    /// `vertexUniforms` is the render event's own: a binding of exactly it records as per-view.
    func beginRecording(cullMode: MTLCullMode, windingOrder: MTLWinding, triangleFillMode: MTLTriangleFillMode, renderOrder: Int, vertexUniforms: VertexUniformsBinding? = nil, debugLabel: @autoclosure () -> String) {
        tables.beginRecording(cullMode: cullMode, windingOrder: windingOrder, triangleFillMode: triangleFillMode, renderOrder: renderOrder, vertexUniforms: vertexUniforms, debugLabel: debugLabel())
    }

    func beginMaterial() { tables.beginMaterial() }
    func endRecording() { tables.endRecording() }
    var recordingPipelineUsage: PipelineResourceUsage? { tables.pendingPipelineUsage }

    func setPipeline(_ pipeline: MTLRenderPipelineState, usage: PipelineResourceUsage? = nil) { tables.setPipeline(pipeline, usage: usage) }

    func setDepthStencilState(_ depthStencilState: MTLDepthStencilState?, bias: DepthBias?, clipMode: MTLDepthClipMode?) {
        tables.setDepthStencilState(depthStencilState, bias: bias, clipMode: clipMode)
    }

    func appendVertexBuffer(_ buffer: MTLBuffer, offset: Int, slot: VertexBufferIndex) {
        tables.appendVertexBuffer(buffer, offset: offset, slot: slot)
    }

    func appendFragmentBuffer(_ buffer: MTLBuffer, offset: Int, slot: FragmentBufferIndex) {
        tables.appendFragmentBuffer(buffer, offset: offset, slot: slot)
    }

    func appendVertexTexture(_ texture: MTLTexture?, slot: VertexTextureIndex) {
        tables.appendVertexTexture(texture, slot: slot)
    }

    func appendFragmentTexture(_ texture: MTLTexture?, slot: FragmentTextureIndex) {
        tables.appendFragmentTexture(texture, slot: slot)
    }

    func appendFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        tables.appendFragmentPBRTexture(texture, type: type)
    }

    func appendFragmentSampler(_ sampler: MTLSamplerState, slot: FragmentSamplerIndex) {
        tables.appendFragmentSampler(sampler, slot: slot)
    }

    func appendObjectBuffer(_ buffer: MTLBuffer, offset: Int, slot: ObjectBufferIndex) {
        tables.appendObjectBuffer(buffer, offset: offset, slot: slot)
    }

    func appendMeshBuffer(_ buffer: MTLBuffer, offset: Int, slot: MeshBufferIndex) {
        tables.appendMeshBuffer(buffer, offset: offset, slot: slot)
    }

    func appendTessellationFactorBuffer(_ buffer: MTLBuffer, offset: Int, instanceStride: Int) {
        tables.appendTessellationFactorBuffer(buffer, offset: offset, instanceStride: instanceStride)
    }

    /// The index buffer of an indexed draw is kept with the other buffers.
    func appendIndexBuffer(_ buffer: MTLBuffer) -> Int32 { tables.appendBuffer(buffer) }

    func finishPacket(drawCall: PacketDrawCall) { tables.finishPacket(drawCall: drawCall) }

    // MARK: Encoding

    /// Replays the packets at `packetIndices`, in order, into `state`, advancing view-following
    /// bindings by the captured byte offset.
    func encode<PacketIndices: Sequence>(_ packetIndices: PacketIndices, into state: RenderEncoderState, viewOffset: Int = 0) where PacketIndices.Element == Int {
        tables.encode(packetIndices, into: state, viewOffset: viewOffset)
    }

    func pipeline(ofPacketAt packetIndex: Int) -> MTLRenderPipelineState {
        tables.pipelines[Int(tables.packets[packetIndex].pipelineIndex)]
    }

    func renderOrder(ofPacketAt packetIndex: Int) -> Int {
        tables.packets[packetIndex].renderOrder
    }
}

/// A `PacketStorage`'s recorded packets, commands and references, and the cursor of the recording in
/// progress. A value, mutated in place: inside its methods every field access is static.
///
/// Every method is `mutating`, reads included: a non-mutating call, on the storage's property or on
/// `self` inside another method, takes a copy of the whole value, a retain and release of every
/// table per call. A mutating one works on the tables in place.
struct PacketTables {
    /// One renderable's packets for one route, in the order recorded: a draw's own scene, and each
    /// `record(scene:)` into its submission.
    struct PacketRun {
        let renderLayer: Int
        let routeIndex: Int
        let packets: Range<Int>
        /// From `record(scene:)`, encoded after the draw's own scene in its layer.
        let isRecorded: Bool
    }

    private(set) var runs = ContiguousArray<PacketRun>()
    private(set) var packets = ContiguousArray<DrawPacket>()
    private(set) var commands = ContiguousArray<PacketCommand>()
    private(set) var buffers = ContiguousArray<MTLBuffer>()
    private(set) var textures = ContiguousArray<MTLTexture>()
    private(set) var samplers = ContiguousArray<MTLSamplerState>()
    private(set) var pipelines = ContiguousArray<MTLRenderPipelineState>()
    private(set) var depthStencilStates = ContiguousArray<MTLDepthStencilState>()
#if DEBUG
    private(set) var debugLabels = ContiguousArray<String>()
#endif

    /// How much of each array a point in recording had used, to roll back to.
    private struct Marks {
        var commands = 0
        var buffers = 0
        var textures = 0
        var samplers = 0
        var pipelines = 0
        var depthStencilStates = 0
    }

    // The packet being built.
    private var packetCommandStart = 0
    private var ownStart = Marks()
    private var prefixLength: Int?
    /// The first buffer entry of the recording in progress: a buffer appended again in the same
    /// recording reuses its entry, never one from an earlier recording.
    private var recordingBufferStart = 0
    private(set) var pendingPipelineUsage: PipelineResourceUsage?
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
    /// The recording's own vertex uniforms, by identity and offset, to record their bindings as
    /// per-view.
    private var recordingVertexUniformsBuffer: ObjectIdentifier?
    private var recordingVertexUniformsOffset = 0

    /// How far back a buffer append looks for an entry to reuse.
    private static let bufferReuseWindow = 16

    mutating func reset() {
        runs.removeAll(keepingCapacity: true)
        packets.removeAll(keepingCapacity: true)
        commands.removeAll(keepingCapacity: true)
        buffers.removeAll(keepingCapacity: true)
        textures.removeAll(keepingCapacity: true)
        samplers.removeAll(keepingCapacity: true)
        pipelines.removeAll(keepingCapacity: true)
        depthStencilStates.removeAll(keepingCapacity: true)
#if DEBUG
        debugLabels.removeAll(keepingCapacity: true)
#endif
    }

    mutating func appendRun(renderLayer: Int, routeIndex: Int, packets: Range<Int>, isRecorded: Bool) {
        guard !packets.isEmpty else { return }
        runs.append(PacketRun(renderLayer: renderLayer, routeIndex: routeIndex, packets: packets, isRecorded: isRecorded))
    }

    // MARK: Recording

    mutating func beginRecording(cullMode: MTLCullMode, windingOrder: MTLWinding, triangleFillMode: MTLTriangleFillMode, renderOrder: Int, vertexUniforms: VertexUniformsBinding?, debugLabel: @autoclosure () -> String) {
        recordingVertexUniformsBuffer = vertexUniforms.map { ObjectIdentifier($0.buffer) }
        recordingVertexUniformsOffset = vertexUniforms?.offset ?? 0
        recordingCullMode = cullMode
        recordingWindingOrder = windingOrder
        recordingTriangleFillMode = triangleFillMode
        recordingRenderOrder = renderOrder
#if DEBUG
        debugLabels.append(debugLabel())
        recordingDebugLabelIndex = Int32(debugLabels.count - 1)
#endif
        packetCommandStart = commands.count
        recordingBufferStart = buffers.count
        prefixLength = nil
        startOwnCommands()
    }

    /// A material is about to record: the packet's own commands start here, without a pipeline.
    mutating func beginMaterial() {
        if prefixLength == nil {
            prefixLength = commands.count - packetCommandStart
        }
        startOwnCommands()
    }

    mutating func endRecording() {
        // Anything recorded after the last draw call draws nothing.
        rollBack(to: Marks(
            commands: packetCommandStart,
            buffers: ownStart.buffers,
            textures: ownStart.textures,
            samplers: ownStart.samplers,
            pipelines: ownStart.pipelines,
            depthStencilStates: ownStart.depthStencilStates
        ))
        prefixLength = nil
    }

    private mutating func startOwnCommands() {
        ownStart = Marks(
            commands: commands.count,
            buffers: buffers.count,
            textures: textures.count,
            samplers: samplers.count,
            pipelines: pipelines.count,
            depthStencilStates: depthStencilStates.count
        )
        pendingPipelineIndex = -1
        pendingPipelineUsage = nil
        pendingDepthStencilStateIndex = -1
        pendingSetsDepthState = false
        pendingDepthBias = nil
        pendingDepthClipMode = nil
    }

    /// Removes every entry and command at or after `marks`. A kept command only references entries
    /// that existed when it was recorded, so it never loses one.
    private mutating func rollBack(to marks: Marks) {
        commands.removeSubrange(marks.commands...)
        buffers.removeSubrange(marks.buffers...)
        textures.removeSubrange(marks.textures...)
        samplers.removeSubrange(marks.samplers...)
        pipelines.removeSubrange(marks.pipelines...)
        depthStencilStates.removeSubrange(marks.depthStencilStates...)
    }

    mutating func setPipeline(_ pipeline: MTLRenderPipelineState, usage: PipelineResourceUsage?) {
        pendingPipelineUsage = usage
        pipelines.append(pipeline)
        pendingPipelineIndex = Int32(pipelines.count - 1)
    }

    mutating func setDepthStencilState(_ depthStencilState: MTLDepthStencilState?, bias: DepthBias?, clipMode: MTLDepthClipMode?) {
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

    mutating func appendVertexBuffer(_ buffer: MTLBuffer, offset: Int, slot: VertexBufferIndex) {
        let bufferIndex = appendBuffer(buffer)
        if isRecordingVertexUniforms(buffer, offset: offset) {
            commands.append(.perViewVertexBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        } else {
            commands.append(.vertexBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        }
    }

    mutating func appendFragmentBuffer(_ buffer: MTLBuffer, offset: Int, slot: FragmentBufferIndex) {
        let bufferIndex = appendBuffer(buffer)
        if isRecordingVertexUniforms(buffer, offset: offset) {
            commands.append(.perViewFragmentBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        } else {
            commands.append(.fragmentBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        }
    }

    private mutating func isRecordingVertexUniforms(_ buffer: MTLBuffer, offset: Int) -> Bool {
        recordingVertexUniformsBuffer == ObjectIdentifier(buffer) && recordingVertexUniformsOffset == offset
    }

    /// The entry of `buffer`: the one it already has in this recording, if among the last few,
    /// otherwise a new one. Commands keep their own offsets, so one entry serves every offset.
    mutating func appendBuffer(_ buffer: MTLBuffer) -> Int32 {
        let searchStart = max(recordingBufferStart, buffers.count - Self.bufferReuseWindow)
        var entryIndex = buffers.count - 1
        while entryIndex >= searchStart {
            if buffers[entryIndex] === buffer { return Int32(entryIndex) }
            entryIndex -= 1
        }
        buffers.append(buffer)
        return Int32(buffers.count - 1)
    }

    mutating func appendVertexTexture(_ texture: MTLTexture?, slot: VertexTextureIndex) {
        commands.append(.vertexTexture(textureIndex: textureIndex(texture), slot: slot))
    }

    mutating func appendFragmentTexture(_ texture: MTLTexture?, slot: FragmentTextureIndex) {
        commands.append(.fragmentTexture(textureIndex: textureIndex(texture), slot: slot))
    }

    mutating func appendFragmentPBRTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        commands.append(.fragmentPBRTexture(textureIndex: textureIndex(texture), type: type))
    }

    mutating func appendFragmentSampler(_ sampler: MTLSamplerState, slot: FragmentSamplerIndex) {
        samplers.append(sampler)
        commands.append(.fragmentSampler(samplerIndex: Int32(samplers.count - 1), slot: slot))
    }

    mutating func appendObjectBuffer(_ buffer: MTLBuffer, offset: Int, slot: ObjectBufferIndex) {
        let bufferIndex = appendBuffer(buffer)
        if isRecordingVertexUniforms(buffer, offset: offset) {
            commands.append(.perViewObjectBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        } else {
            commands.append(.objectBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        }
    }

    mutating func appendMeshBuffer(_ buffer: MTLBuffer, offset: Int, slot: MeshBufferIndex) {
        let bufferIndex = appendBuffer(buffer)
        if isRecordingVertexUniforms(buffer, offset: offset) {
            commands.append(.perViewMeshBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        } else {
            commands.append(.meshBuffer(bufferIndex: bufferIndex, offset: offset, slot: slot))
        }
    }

    mutating func appendTessellationFactorBuffer(_ buffer: MTLBuffer, offset: Int, instanceStride: Int) {
        commands.append(.tessellationFactorBuffer(bufferIndex: appendBuffer(buffer), offset: offset, instanceStride: instanceStride))
    }

    private mutating func textureIndex(_ texture: MTLTexture?) -> Int32 {
        guard let texture else { return -1 }
        textures.append(texture)
        return Int32(textures.count - 1)
    }

    /// Finishes the packet with `drawCall`, or abandons it when no material set a pipeline. The next
    /// packet of the recording starts with a copy of the shared prefix.
    mutating func finishPacket(drawCall: PacketDrawCall) {
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

    /// Replays the packets at `packetIndices` into `state`, each its state, its commands in
    /// recorded order, then its draw call.
    mutating func encode<PacketIndices: Sequence>(_ packetIndices: PacketIndices, into state: RenderEncoderState, viewOffset: Int) where PacketIndices.Element == Int {
        for packetIndex in packetIndices {
            encode(packets[packetIndex], into: state, viewOffset: viewOffset)
        }
    }

    private mutating func encode(_ packet: DrawPacket, into state: RenderEncoderState, viewOffset: Int) {
        let renderEncoder = state.renderEncoder
#if DEBUG
        renderEncoder.pushDebugGroup(debugLabels[Int(packet.debugLabelIndex)])
        defer { renderEncoder.popDebugGroup() }
#endif
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
            case let .perViewVertexBuffer(bufferIndex, offset, slot):
                state.setVertexBuffer(buffers[Int(bufferIndex)], offset: offset + viewOffset, index: slot)
            case let .perViewFragmentBuffer(bufferIndex, offset, slot):
                state.setFragmentBuffer(buffers[Int(bufferIndex)], offset: offset + viewOffset, index: slot)
            case let .vertexTexture(textureIndex, slot):
                state.setVertexTexture(texture(at: textureIndex), index: slot)
            case let .fragmentTexture(textureIndex, slot):
                state.setFragmentTexture(texture(at: textureIndex), index: slot)
            case let .fragmentPBRTexture(textureIndex, type):
                state.setFragmentPBRTexture(texture(at: textureIndex), type: type)
            case let .fragmentSampler(samplerIndex, slot):
                renderEncoder.setFragmentSamplerState(samplers[Int(samplerIndex)], index: slot.rawValue)
            case let .objectBuffer(bufferIndex, offset, slot):
                renderEncoder.setObjectBuffer(buffers[Int(bufferIndex)], offset: offset, index: slot.rawValue)
            case let .meshBuffer(bufferIndex, offset, slot):
                renderEncoder.setMeshBuffer(buffers[Int(bufferIndex)], offset: offset, index: slot.rawValue)
            case let .perViewObjectBuffer(bufferIndex, offset, slot):
                renderEncoder.setObjectBuffer(buffers[Int(bufferIndex)], offset: offset + viewOffset, index: slot.rawValue)
            case let .perViewMeshBuffer(bufferIndex, offset, slot):
                renderEncoder.setMeshBuffer(buffers[Int(bufferIndex)], offset: offset + viewOffset, index: slot.rawValue)
            case let .tessellationFactorBuffer(bufferIndex, offset, instanceStride):
                renderEncoder.setTessellationFactorBuffer(buffers[Int(bufferIndex)], offset: offset, instanceStride: instanceStride)
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
        case let .patches(controlPointCount, patchCount, instanceCount):
            renderEncoder.drawPatches(numberOfPatchControlPoints: controlPointCount, patchStart: 0, patchCount: patchCount,
                                      patchIndexBuffer: nil, patchIndexBufferOffset: 0, instanceCount: instanceCount, baseInstance: 0)
        case let .indexedPatches(controlPointCount, patchCount, controlPointIndexBufferIndex, instanceCount):
            renderEncoder.drawIndexedPatches(numberOfPatchControlPoints: controlPointCount, patchStart: 0, patchCount: patchCount,
                                             patchIndexBuffer: nil, patchIndexBufferOffset: 0,
                                             controlPointIndexBuffer: buffers[Int(controlPointIndexBufferIndex)], controlPointIndexBufferOffset: 0,
                                             instanceCount: instanceCount, baseInstance: 0)
        case let .meshThreadgroups(threadgroups, threadsPerObjectThreadgroup, threadsPerMeshThreadgroup):
            renderEncoder.drawMeshThreadgroups(threadgroups, threadsPerObjectThreadgroup: threadsPerObjectThreadgroup,
                                               threadsPerMeshThreadgroup: threadsPerMeshThreadgroup)
        }
    }

    private mutating func texture(at index: Int32) -> MTLTexture? {
        index >= 0 ? textures[Int(index)] : nil
    }
}

// MARK: - Pool

/// Storage for an encoder's draws: each draw leases one storage and returns it once encoded, so
/// two draws in flight never share or clear each other's packets.
final class PacketStoragePool {
    private var available = ContiguousArray<PacketStorage>()
    private let lock = UnfairLock()

    /// Storages returned and ready to lease.
    var availableCount: Int { lock.sync { available.count } }

    private static let leaseTokenLock = UnfairLock()
    private nonisolated(unsafe) static var lastLeaseToken: UInt64 = 0

    func lease() -> PacketStorage {
        let storage = lock.sync { available.popLast() } ?? PacketStorage()
        storage.leaseToken = Self.leaseTokenLock.sync {
            Self.lastLeaseToken &+= 1
            return Self.lastLeaseToken
        }
        return storage
    }

    func returnStorage(_ storage: PacketStorage) {
        storage.reset()
        lock.sync { available.append(storage) }
    }
}
