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
/// mesh as well) is updated more than once a frame. That is harmless: a draw's palette and
/// uniforms are snapshotted when it is recorded.
open class PosedGeometry: Geometry {
    public let source: Geometry
    private var sourceSubscription: AnyCancellable?

    public init(source: Geometry, jointPalette: JointPalette? = nil) {
        self.source = source
        super.init(context: source.context, primitiveType: source.primitiveType, windingOrder: source.windingOrder)
        self.jointPalette = jointPalette
        // Unowned: the subscription is this object's own, cancelled before it goes, and an unowned
        // capture needs no side table on an object every frame retains.
        sourceSubscription = source.onUpdate.sink { [unowned self] source in
            self.windingOrder = source.windingOrder
            self.updateBounds = true
            self.onUpdate.send(self)
        }
    }

    /// Stops listening before `source` is released: stored properties go in declaration order, so
    /// the subscription would otherwise outlive the start of this view's destruction.
    deinit {
        sourceSubscription?.cancel()
    }

    /// Called each frame after the source updates. Override to recompute the palette from
    /// state that changes over time; the default does nothing.
    open func updatePose() {}

    // MARK: - Forwarded to the source

    override open var vertexDescriptor: MTLVertexDescriptor { source.vertexDescriptor }

    override open var hasVertexBuffers: Bool { source.hasVertexBuffers }

    override open func update() {
        source.update()
        updatePose()
    }

    override open func encode(in context: EncodingContext) throws {
        try source.encode(in: context)
    }

    /// Draws through the source's own `draw(in:)`, with this view's palette replacing the source's
    /// when this view is skinned.
    override open func draw(in context: GeometryDrawContext) throws {
        try source.draw(in: context.replacingJointPalette(isSkinned ? jointPalette : context.jointPalette))
    }

    /// The source's vertices, moved by this view's palette.
    override open var skinningSource: Geometry { source }

    /// The source's pieces: a posed view says what it poses.
    override open var pieces: GeometryPieces? { source.pieces }

    /// The view owns no attributes: the pieces and their joints are the source's.
    override open func setPieces(_ pieces: GeometryPieces?) {
        source.setPieces(pieces)
    }

    /// Posed when skinned (see `Geometry.computeBounds`), otherwise the source's.
    override open func computeBounds() -> Bounds {
        isSkinned ? super.computeBounds() : source.bounds
    }

    override var boundsPaletteDependency: JointPalette? {
        isSkinned ? jointPalette : source.boundsPaletteDependency
    }

    override open func intersect(ray: Ray, intersections: inout [IntersectionResult]) {
        if isSkinned {
            super.intersect(ray: ray, intersections: &intersections)
        } else {
            source.intersect(ray: ray, intersections: &intersections)
        }
    }
}
