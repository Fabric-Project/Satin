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
/// shaders index them by view.
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

/// Records renderables into the packets of one draw, and encodes them. A render event is one
/// occurrence of a renderable in one pass invocation (the colour pass, a shadow light, a point-shadow
/// face): it gets its own vertex uniforms, written from that pass's views and the occurrence's
/// model matrices, which the renderable took once with `beginOccurrence(frame:)` before any pass.
/// Materials, instances and palettes snapshot what they draw with into the same arena.
final class PacketRecorder {
    /// The distance between one view's `VertexUniforms` and the next in a render event's slice.
    static let vertexUniformsStride = MemoryLayout<VertexUniforms>.stride

    let storage: PacketStorage
    let frame: FrameTime
    private let arena: FrameArena
    private let commandBuffer: MTLCommandBuffer

    /// The record in progress; `beginRecord()` starts the next.
    private(set) var recordToken: RecordToken

    init(storage: PacketStorage, arena: FrameArena, commandBuffer: MTLCommandBuffer, frame: FrameTime) {
        self.storage = storage
        self.arena = arena
        self.commandBuffer = commandBuffer
        self.frame = frame
        recordToken = RecordToken(leaseToken: storage.leaseToken, recordIndex: 0)
    }

    /// Starts the next record: what's recorded from here snapshots palettes afresh.
    func beginRecord() {
        recordToken = RecordToken(leaseToken: storage.leaseToken, recordIndex: recordToken.recordIndex + 1)
    }

    /// `length` bytes valid until this draw's command buffer completes, for a snapshot.
    func allocate(length: Int) -> FrameArena.Slice {
        arena.allocate(length: length, alignment: 256, commandBuffer: commandBuffer)
    }

    /// Keeps `owner` alive until this draw's command buffer completes, or its arena region is
    /// reclaimed if the command buffer is never committed.
    func retainUntilCompleted(_ owner: AnyObject) {
        arena.retainUntilCompleted(owner, commandBuffer: commandBuffer)
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
    ) -> Range<Int> {
        let firstPacket = storage.packetCount
        guard !views.isEmpty else { return firstPacket ..< firstPacket }

        // Every view gets its uniforms: the amplified views of one pass, or the views of a
        // multi-view shadow, each encoded in its own pass from this one recording.
        let vertexUniforms = writeVertexUniforms(
            occurrence: renderable.occurrence,
            viewCount: max(renderContext.vertexAmplificationCount, views.count, 1),
            views: views
        )

        // A double-sided transparent renderable is recorded twice, culling front faces and then back
        // faces, so all its back faces draw before its front faces, every submesh in each.
        if pass == .color, renderable.doubleSided, renderable.cullMode == .none, renderable.opaque == false {
            recordOnce(renderable, cullMode: .front, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
            recordOnce(renderable, cullMode: .back, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
        } else {
            recordOnce(renderable, cullMode: renderable.cullMode, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
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
    ) {
        storage.beginRecording(
            cullMode: cullMode,
            windingOrder: renderable.windingOrder,
            triangleFillMode: renderable.triangleFillMode,
            renderOrder: renderable.renderOrder,
            vertexUniforms: vertexUniforms,
            debugLabel: renderable.label
        )
        renderable.draw(in: RenderableDrawContext(
            renderContext: renderContext,
            pass: pass,
            materialPass: materialPass,
            vertexUniforms: vertexUniforms,
            recorder: self
        ))
        storage.endRecording()
    }

    /// Encodes the packets at `packetIndices` into `state`, as their render event's view
    /// `viewIndex`: the first, unless the event was recorded for several views.
    func encode<PacketIndices: Sequence>(_ packetIndices: PacketIndices, into state: RenderEncoderState, viewIndex: Int = 0) where PacketIndices.Element == Int {
        storage.encode(packetIndices, into: state, viewIndex: viewIndex)
    }

    /// One `VertexUniforms` per view, contiguous, in an arena slice valid until the command buffer
    /// completes. A pass with fewer views than the context's repeats its last view.
    private func writeVertexUniforms(occurrence: Renderable.Occurrence, viewCount: Int, views: [RenderView]) -> VertexUniformsBinding {
        let slice = allocate(length: Self.vertexUniformsStride * viewCount)
        let uniforms = slice.contents.bindMemory(to: VertexUniforms.self, capacity: viewCount)
        let modelMatrix = occurrence.modelMatrix
        let previousModelMatrix = occurrence.previousModelMatrix
        for viewIndex in 0 ..< viewCount {
            let view = views[min(viewIndex, views.count - 1)]
            let viewProjectionMatrix = view.viewProjectionMatrix
            let previousViewProjectionMatrix = view.previousViewProjectionMatrix
            let modelViewProjectionMatrix = viewProjectionMatrix * modelMatrix

            uniforms[viewIndex].modelMatrix = modelMatrix
            uniforms[viewIndex].viewMatrix = view.viewMatrix
            uniforms[viewIndex].modelViewMatrix = view.viewMatrix * modelMatrix
            uniforms[viewIndex].projectionMatrix = view.projectionMatrix
            uniforms[viewIndex].viewProjectionMatrix = viewProjectionMatrix
            uniforms[viewIndex].modelViewProjectionMatrix = modelViewProjectionMatrix
            uniforms[viewIndex].inverseModelViewProjectionMatrix = modelViewProjectionMatrix.inverse
            uniforms[viewIndex].inverseViewMatrix = view.inverseViewMatrix
            uniforms[viewIndex].normalMatrix = occurrence.normalMatrix
            uniforms[viewIndex].viewport = view.viewport
            uniforms[viewIndex].worldCameraPosition = view.worldPosition
            uniforms[viewIndex].worldCameraViewDirection = view.viewDirection
            uniforms[viewIndex].previousModelMatrix = previousModelMatrix
            uniforms[viewIndex].previousViewProjectionMatrix = previousViewProjectionMatrix
            uniforms[viewIndex].previousModelViewProjectionMatrix = previousViewProjectionMatrix * previousModelMatrix
        }
        return VertexUniformsBinding(buffer: slice.buffer, offset: slice.offset)
    }
}
