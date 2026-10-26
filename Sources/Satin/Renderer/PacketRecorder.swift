//
//  PacketRecorder.swift
//  Satin
//

import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// Where a render event's vertex uniforms live: one `VertexUniforms` per view, contiguous, as the
/// shaders index them by view. Reserved while recording and written when the submission encodes,
/// so a binding is for binding: its bytes aren't there yet while recording.
public struct VertexUniformsBinding {
    public let buffer: MTLBuffer
    public let offset: Int
}

/// One record into a lease: a draw's own scene, or one `record(scene:)`. Unique process-wide, as
/// lease tokens are, so a palette shared by several meshes snapshots and advances once per record.
struct RecordToken: Equatable {
    let leaseToken: UInt64
    let recordIndex: Int
}

/// Pass-wide data belongs to the recording, never to an advancing StructBuffer ring.
struct RenderPassBindings {
    var lights: FrameArena.Slice?
    var bindsLights = false
    var shadowData: FrameArena.Slice?
    var shadowMatrices: FrameArena.Slice?
    var projectorMatrices: FrameArena.Slice?
    var projectorTransforms: FrameArena.Slice?
    var shadowTextures: [MTLTexture?] = []
    var projectorTextures: [MTLTexture?] = []

    func apply(to state: RenderEncoderState) {
        if bindsLights, let lights { state.setPassFragmentBuffer(lights.buffer, offset: lights.offset, index: .Lighting) }
        func bind(_ slice: FrameArena.Slice?, at index: FragmentBufferIndex) {
            guard let slice else { return }
            state.setPassFragmentBuffer(slice.buffer, offset: slice.offset, index: index)
            state.renderEncoder.useResource(slice.buffer, usage: .read, stages: .fragment)
        }
        bind(shadowData, at: .DirectShadows)
        bind(shadowMatrices, at: .DirectShadowMatrices)
        bind(projectorMatrices, at: .ProjectorMatrices)
        bind(projectorTransforms, at: .ProjectorTransforms)
        if !shadowTextures.isEmpty {
            state.setPassFragmentTextures(shadowTextures, range: FragmentTextureIndex.DirectShadow0.rawValue ..< FragmentTextureIndex.DirectShadow0.rawValue + shadowTextures.count)
        }
        if !projectorTextures.isEmpty {
            state.setPassFragmentTextures(projectorTextures, range: FragmentTextureIndex.Projector0.rawValue ..< FragmentTextureIndex.Projector0.rawValue + projectorTextures.count)
        }
        for texture in shadowTextures {
            if let texture { state.renderEncoder.useResource(texture, usage: .read, stages: .fragment) }
        }
        for texture in projectorTextures {
            if let texture { state.renderEncoder.useResource(texture, usage: .read, stages: .fragment) }
        }
    }

}

/// Records renderables into the packets of one draw, and encodes them. A render event is one
/// occurrence of a renderable in one pass invocation (the colour pass, a shadow light, a point-shadow
/// face): it gets its own vertex uniforms, written from that pass's views and the occurrence's
/// model matrices, which the renderable took once with `beginOccurrence(frame:)` before any pass.
/// Materials, instances and palettes snapshot what they draw with into the same arena.
public final class PacketRecorder {
    /// The distance between one view's `VertexUniforms` and the next in a render event's slice.
    static let vertexUniformsStride = MemoryLayout<VertexUniforms>.stride

    /// The distance between views of an event recorded for several views without amplification,
    /// each encoded in its own pass: every view starts on a 256-byte boundary, as a single-view
    /// event's uniforms do. Amplified views stay contiguous, as the shaders index them by view.
    static let viewSlotStride = (vertexUniformsStride + 255) / 256 * 256

    /// The view spacing for separately encoded views.
    let recordedViewStride = PacketRecorder.viewSlotStride
    /// The views the last reservation used, in the storage's view table.
    private var lastViewRange: Range<Int>?

    var passBindings = RenderPassBindings()
    var defersLightingPipelines = false
    var shadowInvalidations: [ShadowRecordingInvalidation] = []
    let storage: PacketStorage
    let frame: FrameTime
    private let lease: FrameArena.Lease

    /// The record in progress; `beginRecord()` starts the next.
    private(set) var recordToken: RecordToken

    private var preparationSerial = 0
    private var retainedPreparationSerial = -1

    /// Contexts normally allocate nothing. An integer local to this recorder lets each context
    /// retain preparation storage only when it first allocates, without a per-context wrapper.
    func beginPreparation() -> Int {
        preparationSerial += 1
        return preparationSerial
    }

    func retainArena(for preparation: Int, untilCompleted commandBuffer: MTLCommandBuffer) {
        guard retainedPreparationSerial != preparation else { return }
        lease.retain(untilCompleted: commandBuffer)
        retainedPreparationSerial = preparation
    }

    /// Allocation and snapshots come from the frame's lease: recording needs no command buffer.
    init(storage: PacketStorage, lease: FrameArena.Lease) {
        self.storage = storage
        self.lease = lease
        frame = lease.frame
        recordToken = RecordToken(leaseToken: storage.leaseToken, recordIndex: 0)
    }

    /// Starts the next record: what's recorded from here snapshots palettes afresh.
    func beginRecord() {
        recordToken = RecordToken(leaseToken: storage.leaseToken, recordIndex: recordToken.recordIndex + 1)
    }

    /// `length` bytes valid until this draw's command buffer completes, for a snapshot.
    func allocate(length: Int) throws -> FrameArena.Slice {
        try lease.allocate(length: length)
    }

    /// Copies pass data at its stride, into storage unique to this recording.
    func snapshot<Sample>(_ values: [Sample]) throws -> FrameArena.Slice? {
        guard !values.isEmpty else { return nil }
        let slice = try allocate(length: MemoryLayout<Sample>.stride * values.count)
        values.withUnsafeBytes { bytes in
            if let source = bytes.baseAddress {
                slice.contents.copyMemory(from: source, byteCount: bytes.count)
            }
        }
        return slice
    }

    /// Opt-in snapshot for CPU-readable external data. By default (nil) bindings retain their
    /// buffer and the caller must leave its bytes unchanged until completion. Copying preserves
    /// `copyOnRecordLength` bytes from the binding offset, at a new aligned offset in the arena.
    func bufferBinding(_ buffer: MTLBuffer, offset: Int, copyOnRecordLength: Int?) throws -> (buffer: MTLBuffer, offset: Int) {
        guard let length = copyOnRecordLength else { return (buffer, offset) }
        precondition(buffer.storageMode != .private && buffer.storageMode != .memoryless, "copyOnRecord requires CPU-readable storage")
        precondition(offset >= 0 && length > 0 && offset + length <= buffer.length, "The copied range must be inside the buffer")
        precondition(!storage.reservesVertexUniforms(in: buffer, range: offset ..< offset + length),
                     "A render event's vertex uniforms are written when the submission encodes: bind them, don't copy them")
        let slice = try allocate(length: length)
        slice.contents.copyMemory(from: buffer.contents() + offset, byteCount: length)
        return (slice.buffer, slice.offset)
    }

    /// Records one render event of `renderable` and returns the packets it produced: none when it
    /// draws nothing in this pass (no pipeline, no matching material, nothing to draw).
    @discardableResult
    func record(
        _ renderable: Renderable,
        renderContext: Context,
        pass: RenderPass,
        materialPass: Renderable.MaterialPass,
        views: [RenderView]
    ) throws -> Range<Int> {
        let firstPacket = storage.packetCount
        guard !views.isEmpty else { return firstPacket ..< firstPacket }

        // Every view gets its uniforms: the amplified views of one pass, or the views of a
        // multi-view shadow, each encoded in its own pass from this one recording.
        let isAmplified = renderContext.vertexAmplificationCount > 1
        let vertexUniforms = try reserveVertexUniforms(
            occurrence: renderable.occurrence,
            viewCount: max(renderContext.vertexAmplificationCount, views.count, 1),
            viewStride: isAmplified ? Self.vertexUniformsStride : recordedViewStride,
            views: views
        )

        // A double-sided transparent renderable is recorded twice, culling front faces and then back
        // faces, so all its back faces draw before its front faces, every submesh in each.
        if pass == .color, renderable.doubleSided, renderable.cullMode == .none, renderable.drawsTransparent(in: materialPass) {
            try recordOnce(renderable, cullMode: .front, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
            try recordOnce(renderable, cullMode: .back, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
        } else {
            try recordOnce(renderable, cullMode: renderable.cullMode, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
        }

        return firstPacket ..< storage.packetCount
    }

    private func recordOnce(
        _ renderable: Renderable,
        cullMode: MTLCullMode,
        renderContext: Context,
        pass: RenderPass,
        materialPass: Renderable.MaterialPass,
        vertexUniforms: VertexUniformsBinding
    ) throws {
        storage.beginRecording(
            cullMode: cullMode,
            windingOrder: renderable.windingOrder,
            triangleFillMode: renderable.triangleFillMode,
            renderOrder: renderable.renderOrder,
            vertexUniforms: vertexUniforms,
            debugLabel: renderable.label
        )
        defer { storage.endRecording() }
        try renderable.draw(in: RenderableDrawContext(
            renderContext: renderContext,
            pass: pass,
            materialPass: materialPass,
            vertexUniforms: vertexUniforms,
            recorder: self
        ))
    }

    /// Encodes the packets at `packetIndices` into `state`, as their render event's view
    /// `viewIndex`: the first, unless the event was recorded for several views.
    func encode<PacketIndices: Sequence>(_ packetIndices: PacketIndices, into state: RenderEncoderState, viewIndex: Int = 0) where PacketIndices.Element == Int {
        storage.encode(packetIndices, into: state, viewOffset: viewIndex * recordedViewStride)
    }

    /// Reserves one `VertexUniforms` per view, `viewStride` apart, in an arena slice valid until the
    /// command buffer completes, and queues their write from the occurrence and the views as values.
    /// The slot is bound by hooks now and filled when the submission encodes. A pass with fewer views
    /// than the context's repeats its last view.
    func reserveVertexUniforms(occurrence: Renderable.Occurrence, viewCount: Int, viewStride: Int, views: [RenderView]) throws -> VertexUniformsBinding {
        let slice = try allocate(length: viewStride * (viewCount - 1) + Self.vertexUniformsStride)
        storage.appendVertexUniformsJob(VertexUniformsJob(
            slice: slice,
            modelMatrix: occurrence.modelMatrix,
            previousModelMatrix: occurrence.previousModelMatrix,
            normalMatrix: occurrence.normalMatrix,
            views: viewRange(for: views),
            viewCount: viewCount,
            viewStride: viewStride
        ))
        return VertexUniformsBinding(buffer: slice.buffer, offset: slice.offset)
    }

    /// Where `views` sit in the storage's view table. Records usually share their views (every
    /// renderable of a colour pass, every caster of a shadow batch), so the last set is reused when
    /// it matches and appended only when it doesn't.
    private func viewRange(for views: [RenderView]) -> Range<Int> {
        if let lastViewRange, lastViewRange.count == views.count {
            var matches = true
            for index in views.indices where !Self.isSameView(storage.viewTable[lastViewRange.lowerBound + index], views[index]) {
                matches = false
                break
            }
            if matches { return lastViewRange }
        }
        let range = storage.appendViews(views)
        lastViewRange = range
        return range
    }

    private static func isSameView(_ first: RenderView, _ second: RenderView) -> Bool {
        first.viewMatrix == second.viewMatrix
            && first.projectionMatrix == second.projectionMatrix
            && first.viewProjectionMatrix == second.viewProjectionMatrix
            && first.inverseViewMatrix == second.inverseViewMatrix
            && first.previousViewProjectionMatrix == second.previousViewProjectionMatrix
            && first.viewport == second.viewport
            && first.worldPosition == second.worldPosition
            && first.viewDirection == second.viewDirection
    }
}

/// One render event's vertex uniforms, as values: where they go, the occurrence's transforms and
/// which views of the storage's view table. Written off the producer, reading no live object.
struct VertexUniformsJob {
    let slice: FrameArena.Slice
    let modelMatrix: simd_float4x4
    let previousModelMatrix: simd_float4x4
    let normalMatrix: simd_float3x3
    let views: Range<Int>
    let viewCount: Int
    let viewStride: Int

    func write(from viewTable: ContiguousArray<RenderView>) {
        for viewIndex in 0 ..< viewCount {
            let uniforms = (slice.contents + viewIndex * viewStride).bindMemory(to: VertexUniforms.self, capacity: 1)
            let view = viewTable[views.lowerBound + min(viewIndex, views.count - 1)]
            let viewProjectionMatrix = view.viewProjectionMatrix
            let previousViewProjectionMatrix = view.previousViewProjectionMatrix
            let modelViewProjectionMatrix = viewProjectionMatrix * modelMatrix

            uniforms.pointee.modelMatrix = modelMatrix
            uniforms.pointee.viewMatrix = view.viewMatrix
            uniforms.pointee.modelViewMatrix = view.viewMatrix * modelMatrix
            uniforms.pointee.projectionMatrix = view.projectionMatrix
            uniforms.pointee.viewProjectionMatrix = viewProjectionMatrix
            uniforms.pointee.modelViewProjectionMatrix = modelViewProjectionMatrix
            uniforms.pointee.inverseModelViewProjectionMatrix = modelViewProjectionMatrix.inverse
            uniforms.pointee.inverseViewMatrix = view.inverseViewMatrix
            uniforms.pointee.normalMatrix = normalMatrix
            uniforms.pointee.viewport = view.viewport
            uniforms.pointee.worldCameraPosition = view.worldPosition
            uniforms.pointee.worldCameraViewDirection = view.viewDirection
            uniforms.pointee.previousModelMatrix = previousModelMatrix
            uniforms.pointee.previousViewProjectionMatrix = previousViewProjectionMatrix
            uniforms.pointee.previousModelViewProjectionMatrix = previousViewProjectionMatrix * previousModelMatrix
        }
    }
}
