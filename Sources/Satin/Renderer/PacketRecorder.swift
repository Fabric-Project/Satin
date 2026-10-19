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

/// Records renderables into the packets of one draw, and encodes them. A render event is one
/// occurrence of a renderable in one pass invocation (the colour pass, a shadow light, a point-shadow
/// face): it gets its own vertex uniforms, written from that pass's views and the occurrence's
/// model matrices, which the renderable took once with `beginOccurrence(frame:)` before any pass.
final class PacketRecorder {
    /// The distance between one view's `VertexUniforms` and the next in a render event's slice.
    static let vertexUniformsStride = MemoryLayout<VertexUniforms>.stride

    let storage: PacketStorage
    let frame: FrameTime
    private let arena: FrameArena
    private let commandBuffer: MTLCommandBuffer

    init(storage: PacketStorage, arena: FrameArena, commandBuffer: MTLCommandBuffer, frame: FrameTime) {
        self.storage = storage
        self.arena = arena
        self.commandBuffer = commandBuffer
        self.frame = frame
    }

    /// Records one render event of `renderable` and returns the packets it produced: none when it
    /// draws nothing in this pass (no pipeline, no matching material, nothing to draw).
    @discardableResult
    func record(
        _ renderable: Renderable,
        renderContext: Context,
        pass: RenderPass,
        materialPass: Renderable.MaterialPass,
        cameras: [Camera],
        viewports: [simd_float4]
    ) -> Range<Int> {
        let firstPacket = storage.packets.count
        guard !cameras.isEmpty, !viewports.isEmpty else { return firstPacket ..< firstPacket }

        let vertexUniforms = writeVertexUniforms(
            occurrence: renderable.occurrence,
            viewCount: max(renderContext.vertexAmplificationCount, 1),
            cameras: cameras,
            viewports: viewports
        )

        // A double-sided transparent renderable is recorded twice, culling front faces and then back
        // faces, so all its back faces draw before its front faces, every submesh in each.
        if pass == .color, renderable.doubleSided, renderable.cullMode == .none, renderable.opaque == false {
            recordOnce(renderable, cullMode: .front, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
            recordOnce(renderable, cullMode: .back, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
        } else {
            recordOnce(renderable, cullMode: renderable.cullMode, renderContext: renderContext, pass: pass, materialPass: materialPass, vertexUniforms: vertexUniforms)
        }

        return firstPacket ..< storage.packets.count
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
            debugLabel: renderable.label
        )
        if let preDraw = renderable.preDraw {
            storage.appendCustomCommand(preDraw)
        }
        renderable.draw(in: RenderableDrawContext(
            renderContext: renderContext,
            pass: pass,
            materialPass: materialPass,
            vertexUniforms: vertexUniforms,
            storage: storage
        ))
        storage.endRecording()
    }

    func encode(_ packets: Range<Int>, into state: RenderEncoderState) {
        for packetIndex in packets {
            storage.encode(storage.packets[packetIndex], into: state)
        }
    }

    func encode(_ packetIndices: ArraySlice<Int>, into state: RenderEncoderState) {
        for packetIndex in packetIndices {
            storage.encode(storage.packets[packetIndex], into: state)
        }
    }

    /// One `VertexUniforms` per view, contiguous, in an arena slice valid until the command buffer
    /// completes. A pass with fewer cameras than views repeats its last camera.
    private func writeVertexUniforms(occurrence: Renderable.Occurrence, viewCount: Int, cameras: [Camera], viewports: [simd_float4]) -> VertexUniformsBinding {
        let slice = arena.allocate(length: Self.vertexUniformsStride * viewCount, alignment: 256, commandBuffer: commandBuffer)
        let uniforms = slice.contents.bindMemory(to: VertexUniforms.self, capacity: viewCount)
        let modelMatrix = occurrence.modelMatrix
        let previousModelMatrix = occurrence.previousModelMatrix
        for view in 0 ..< viewCount {
            let camera = cameras[min(view, cameras.count - 1)]
            let viewProjectionMatrix = camera.viewProjectionMatrix
            let previousViewProjectionMatrix = camera.previousViewProjectionMatrix(frame: frame)
            let modelViewProjectionMatrix = viewProjectionMatrix * modelMatrix

            uniforms[view].modelMatrix = modelMatrix
            uniforms[view].viewMatrix = camera.viewMatrix
            uniforms[view].modelViewMatrix = camera.viewMatrix * modelMatrix
            uniforms[view].projectionMatrix = camera.projectionMatrix
            uniforms[view].viewProjectionMatrix = viewProjectionMatrix
            uniforms[view].modelViewProjectionMatrix = modelViewProjectionMatrix
            uniforms[view].inverseModelViewProjectionMatrix = modelViewProjectionMatrix.inverse
            uniforms[view].inverseViewMatrix = camera.worldMatrix
            uniforms[view].normalMatrix = occurrence.normalMatrix
            uniforms[view].viewport = viewports[min(view, viewports.count - 1)]
            uniforms[view].worldCameraPosition = camera.worldPosition
            uniforms[view].worldCameraViewDirection = camera.viewDirection
            uniforms[view].previousModelMatrix = previousModelMatrix
            uniforms[view].previousViewProjectionMatrix = previousViewProjectionMatrix
            uniforms[view].previousModelViewProjectionMatrix = previousViewProjectionMatrix * previousModelMatrix
        }
        return VertexUniformsBinding(buffer: slice.buffer, offset: slice.offset)
    }
}
