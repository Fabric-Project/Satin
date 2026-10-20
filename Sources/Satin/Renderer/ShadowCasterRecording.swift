//
//  ShadowCasterRecording.swift
//  Satin
//

import Metal
import simd

/// Draws a frame's shadows: every pass of every shadow (a point light's six faces, a spot or
/// directional light's one) is a view, each caster is recorded once for all of them, and each pass
/// encodes it as its own view, skipping the passes its world bounds can't reach.
///
/// A caster whose recording can't serve every view (it runs a custom command, which may have
/// captured the first view's uniforms, or the context amplifies, so its views are laid out for the
/// shaders) is recorded again for each pass it reaches. Views are recorded in batches of at most
/// `maximumViewsPerRecording`, whole shadows at a time, to bound each recording's uniforms.
final class ShadowCasterRecording {
    static let maximumViewsPerRecording = 32

    /// One pass: which shadow draws it, and which of its passes it is.
    private struct Pass {
        let shadow: Shadow
        let passIndex: Int
    }

    /// One caster's recording for this batch, and the passes it may reach.
    private struct Caster {
        let renderable: Renderable
        let packets: Range<Int>
        /// Bit k: the caster may reach pass k of the batch.
        let passes: UInt64
        /// Whether the one recording encodes correctly as any pass's view.
        let servesEveryView: Bool
    }

    // Reused every frame, keeping capacity.
    private var batch = ContiguousArray<Shadow>()
    private var passes = ContiguousArray<Pass>()
    private var views: [RenderView] = []
    private var frusta = ContiguousArray<ViewFrustum>()
    private var casters = ContiguousArray<Caster>()

    /// Draws `shadows`' maps from `renderables`' casters into `recorder`'s draw.
    func draw(_ shadows: ContiguousArray<Shadow>, context: Context, commandBuffer: MTLCommandBuffer, renderables: ContiguousArray<Renderable>, recorder: PacketRecorder) {
        let state = RenderEncoderState()
        for pass in prepare(shadows, context: context, renderables: renderables, recorder: recorder) {
            pass.encode(into: commandBuffer, recorder: recorder, state: state)
        }
    }

    func prepare(_ shadows: ContiguousArray<Shadow>, context: Context, renderables: ContiguousArray<Renderable>, recorder: PacketRecorder) -> [RecordedRenderPass] {
        var result: [RecordedRenderPass] = []
        batch.removeAll(keepingCapacity: true)
        var batchViewCount = 0
        for shadow in shadows {
            if !batch.isEmpty, batchViewCount + shadow.passCount > Self.maximumViewsPerRecording {
                prepareBatch(context: context, renderables: renderables, recorder: recorder, result: &result)
                batch.removeAll(keepingCapacity: true)
                batchViewCount = 0
            }
            batch.append(shadow)
            batchViewCount += shadow.passCount
        }
        if !batch.isEmpty {
            prepareBatch(context: context, renderables: renderables, recorder: recorder, result: &result)
        }
        batch.removeAll(keepingCapacity: true)
        return result
    }

    private func prepareBatch(context: Context, renderables: ContiguousArray<Renderable>, recorder: PacketRecorder, result: inout [RecordedRenderPass]) {
        passes.removeAll(keepingCapacity: true)
        views.removeAll(keepingCapacity: true)
        frusta.removeAll(keepingCapacity: true)
        for shadow in batch {
            shadow.prepareForDrawing(context: context)
            let viewport = shadow.passViewport
            for passIndex in 0 ..< shadow.passCount {
                let view = RenderView(camera: shadow.passCamera(passIndex), viewport: viewport, frame: recorder.frame)
                passes.append(Pass(shadow: shadow, passIndex: passIndex))
                views.append(view)
                frusta.append(ViewFrustum(viewProjectionMatrix: view.viewProjectionMatrix))
            }
        }

        let recordsOnce = PointShadow.recordsCastersOnceForAllFaces
        let allPasses: UInt64 = passes.count >= 64 ? .max : (UInt64(1) << UInt64(passes.count)) - 1

        casters.removeAll(keepingCapacity: true)
        for renderable in renderables where renderable.castShadow {
            var reached = allPasses
            if renderable.frustumCulled {
                let bounds = renderable.worldBounds
                reached = 0
                var shadowReaches = false
                for (index, pass) in passes.enumerated() {
                    if pass.passIndex == 0 { shadowReaches = pass.shadow.mayReach(bounds) }
                    if shadowReaches, frusta[index].mayContain(bounds) {
                        reached |= UInt64(1) << UInt64(index)
                    }
                }
            }
            guard reached != 0 else { continue }

            if recordsOnce {
                let packets = recorder.record(renderable, renderContext: context, pass: .shadow, materialPass: .all, views: views)
                casters.append(Caster(
                    renderable: renderable,
                    packets: packets,
                    passes: reached,
                    // Amplified uniforms are contiguous for the shaders, not laid out per pass.
                    servesEveryView: context.vertexAmplificationCount <= 1 && recorder.storage.packetsServeEveryView(packets)
                ))
            } else {
                casters.append(Caster(renderable: renderable, packets: 0 ..< 0, passes: reached, servesEveryView: false))
            }
        }

        for (index, pass) in passes.enumerated() {
            guard let texture = pass.shadow.passTexture(pass.passIndex) else { continue }
            let descriptor = MTLRenderPassDescriptor()
            descriptor.defaultRasterSampleCount = context.sampleCount
            descriptor.depthAttachment.texture = texture
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 0
            descriptor.renderTargetWidth = texture.width
            descriptor.renderTargetHeight = texture.height
            let viewport = MTLViewport(originX: 0, originY: 0, width: Double(texture.width), height: Double(texture.height), znear: 0, zfar: 1)
            let label = pass.shadow.passCount > 1 ? "\(pass.shadow.label) Shadow Encoder \(pass.passIndex)" : pass.shadow.label + " Shadow Encoder"
            var planned = RecordedRenderPass(descriptor: descriptor, label: label, viewports: [viewport])
            for caster in casters where caster.passes & (UInt64(1) << UInt64(index)) != 0 {
                if caster.servesEveryView {
                    planned.commands.append(.range(caster.packets, viewIndex: index))
                } else {
                    let packets = recorder.record(caster.renderable, renderContext: context, pass: .shadow, materialPass: .all, views: [views[index]])
                    planned.commands.append(.range(packets, viewIndex: 0))
                }
            }
            if pass.passIndex == pass.shadow.passCount - 1 {
                planned.shadowCompletion = pass.shadow.recordingCompletion()
            }
            result.append(planned)
        }

        casters.removeAll(keepingCapacity: true)
        passes.removeAll(keepingCapacity: true)
    }
}
