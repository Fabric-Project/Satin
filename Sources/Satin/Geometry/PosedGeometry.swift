//
//  PosedGeometry.swift
//  Satin
//

import Combine
import Metal

/// Draws another geometry's vertex and index buffers with its own joint palette, so one
/// skinned geometry can be posed several ways at once without copying its vertices. The
/// source's own palette, if any, is left alone.
///
/// The view owns no attributes: its vertex layout, buffers and draw call are the source's.
/// When skinned, its bounds and ray hits follow this view's pose (the source's vertices
/// skinned on the CPU, only when asked for after the pose changed); otherwise they are the
/// source's. Changes to the source reach meshes drawing the view.
///
/// Updating the view updates the source, so a source drawn by several views (or by its own
/// mesh as well) is updated more than once a frame. That is harmless unless its data
/// changes every frame while drawn with repeated encoding, where each update takes a
/// versioned slot.
open class PosedGeometry: Geometry {
    public let source: Geometry
    private var sourceSubscription: AnyCancellable?

    public init(source: Geometry, jointPalette: JointPalette? = nil) {
        self.source = source
        super.init(context: source.context, primitiveType: source.primitiveType, windingOrder: source.windingOrder)
        self.jointPalette = jointPalette
        sourceSubscription = source.onUpdate.sink { [weak self] source in
            guard let self else { return }
            self.windingOrder = source.windingOrder
            self.updateBounds = true
            self.onUpdate.send(self)
        }
    }

    /// Called each frame after the source updates. Override to recompute the palette from
    /// state that changes over time; the default does nothing.
    open func updatePose() {}

    // MARK: - Forwarded to the source

    override open var vertexDescriptor: MTLVertexDescriptor { source.vertexDescriptor }

    override open var hasVertexBuffers: Bool { source.hasVertexBuffers }

    /// Skinned by this view's palette when the source has the joint attributes it applies to.
    override open var isSkinned: Bool {
        jointPalette != nil && source.hasAttribute(.JointIndices) && source.hasAttribute(.JointWeights)
    }

    override open func update() {
        source.update()
        updatePose()
    }

    override open func encode(_ commandBuffer: MTLCommandBuffer) {
        source.encode(commandBuffer)
    }

    // TODO(render-packets): repeated-encoding stopgap; see Renderable.prepareForRepeatedEncoding.
    override open func setMinimumEncodesPerFrame(_ encodesPerFrame: Int) {
        // Never lower what another mesh drawing the source asked for.
        source.setMinimumEncodesPerFrame(max(encodesPerFrame, source.minimumEncodesPerFrame))
        // This view's own palette.
        super.setMinimumEncodesPerFrame(encodesPerFrame)
    }

    override open func captureRepeatedEncoding(iteration: Int, count: Int) {
        source.captureRepeatedEncoding(iteration: iteration, count: count)
        super.captureRepeatedEncoding(iteration: iteration, count: count)
    }

    override open func selectRecentSlot(iteration: Int, count: Int) {
        source.selectRecentSlot(iteration: iteration, count: count)
        jointPalette?.selectRecentSlot(iteration: iteration, count: count)
    }

    override open func bind(renderEncoderState: RenderEncoderState, shadow: Bool) {
        source.bind(renderEncoderState: renderEncoderState, shadow: shadow)
        // Replaces any palette the source bound.
        if isSkinned, let jointPalette {
            renderEncoderState.vertexJointPalette = jointPalette
        }
    }

    override open func draw(renderEncoderState: RenderEncoderState, instanceCount: Int, indexBufferOffset: Int = 0, vertexStart: Int = 0) {
        source.draw(renderEncoderState: renderEncoderState, instanceCount: instanceCount, indexBufferOffset: indexBufferOffset, vertexStart: vertexStart)
    }

    /// The source's vertices, moved by this view's palette.
    override open var skinningSource: Geometry { source }

    /// The source's pieces: a posed view says what it poses.
    override open var pieces: GeometryPieces? {
        get { source.pieces }
        set { source.pieces = newValue }
    }

    /// Posed when skinned (see `Geometry.computeBounds`), otherwise the source's.
    override open func computeBounds() -> Bounds {
        isSkinned ? super.computeBounds() : source.bounds
    }

    override open func intersect(ray: Ray, intersections: inout [IntersectionResult]) {
        if isSkinned {
            super.intersect(ray: ray, intersections: &intersections)
        } else {
            source.intersect(ray: ray, intersections: &intersections)
        }
    }
}
