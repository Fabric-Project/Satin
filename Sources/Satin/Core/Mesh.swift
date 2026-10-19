//
//  Mesh.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// What a draw needs from a material's pipeline that belongs to the mesh, not the material:
/// the geometry's vertex layout, whether it is skinned, whether the mesh is instanced, and
/// whether it casts and receives shadows.
///
/// Contract: a mesh states these at every draw, and the material compiles a pipeline variant
/// for each combination it is drawn with. Meshes never write them into a material, so one
/// material can be shared by any meshes. A material's own vertex layout is only a default:
/// the pipeline compiled first, and the one used by draws that state no layout.
public struct DrawLayout {
    public let vertexDescriptor: MTLVertexDescriptor
    /// `vertexDescriptor`'s interned layout, which pipeline lookups key by.
    public let vertexLayoutID: Int
    public let skinning: Bool
    public let instancing: Bool
    public let castShadow: Bool
    public let receiveShadow: Bool

    public init(vertexDescriptor: MTLVertexDescriptor, vertexLayoutID: Int, skinning: Bool, instancing: Bool, castShadow: Bool, receiveShadow: Bool) {
        self.vertexDescriptor = vertexDescriptor
        self.vertexLayoutID = vertexLayoutID
        self.skinning = skinning
        self.instancing = instancing
        self.castShadow = castShadow
        self.receiveShadow = receiveShadow
    }
}

open class Mesh: Renderable {

    override public var windingOrder: MTLWinding {
        get {
            geometry.windingOrder
        }
        set {
            geometry.windingOrder = newValue
        }
    }

    /// Whether this mesh draws instances; InstancedMesh overrides it.
    open var isInstanced: Bool { false }

    /// What this mesh's draws need from a material's pipeline; see `DrawLayout`.
    public var drawLayout: DrawLayout {
        let geometry: Geometry = self.geometry
        let vertexDescriptor = geometry.vertexDescriptor
        let jointPalette = geometry.jointPalette
        if let cachedDrawLayout,
           cachedDrawLayoutGeometry === geometry,
           cachedDrawLayout.vertexDescriptor === vertexDescriptor,
           cachedDrawLayoutJointPalette === jointPalette,
           cachedDrawLayout.castShadow == castShadow,
           cachedDrawLayout.receiveShadow == receiveShadow
        {
            return cachedDrawLayout
        }

        let drawLayout = DrawLayout(vertexDescriptor: vertexDescriptor, vertexLayoutID: geometry.vertexLayoutID, skinning: geometry.isSkinned, instancing: isInstanced,
                                    castShadow: castShadow, receiveShadow: receiveShadow)
        cachedDrawLayout = drawLayout
        cachedDrawLayoutGeometry = geometry
        cachedDrawLayoutJointPalette = jointPalette
        return drawLayout
    }

    // `drawLayout` is read for every draw and every drawability check; it is rebuilt only when
    // its inputs change. A geometry replaces its vertex descriptor whenever its attributes change,
    // so comparing the geometry, its descriptor and its palette by identity is enough.
    private var cachedDrawLayout: DrawLayout?
    private var cachedDrawLayoutGeometry: Geometry?
    private var cachedDrawLayoutJointPalette: JointPalette?

    override open func isDrawable(renderContext: Context, shadow: Bool) -> Bool {
        guard instanceCount > 0,
              geometry.hasVertexBuffers,
              vertexUniforms(for: renderContext.id) != nil
        else { return false }

        let layout = drawLayout
        if submeshes.isEmpty,
           let material = material,
           materialMatchesCurrentPass(material, shadow: shadow),
           material.getPipeline(renderContext: renderContext, shadow: shadow, layout: layout) != nil
        {
            return true
        } else if submeshes.contains(where: {
            $0.visible &&
                materialMatchesCurrentPass($0.material, shadow: shadow) &&
                $0.material?.getPipeline(renderContext: renderContext, shadow: shadow, layout: layout) != nil
        }) {
            return true
        } else {
            return false
        }
    }

    public let instanceCountPublisher = PassthroughSubject<Int, Never>()
    public var instanceCount = 1 {
        didSet {
            instanceCountPublisher.send(instanceCount)
        }
    }


    open var geometry: Geometry! {
        didSet {
            if geometry != oldValue {
                setupGeometry()
                geometry.setMinimumEncodesPerFrame(minimumEncodesPerFrame)
                _updateLocalBounds = true
            }
        }
    }
    
    override open var material: Material? {
        didSet {
            if material != oldValue {
                setupMaterial()
            }
        }
    }

    var geometrySubscription: AnyCancellable?
    private weak var boundsJointPalette: JointPalette?
    private var boundsPoseVersion = -1
    private var minimumEncodesPerFrame = 1

    public internal(set) var submeshes: [Submesh] = []
    {
        didSet {
            self.updateAllMaterials()
        }
    }

    public init(context: Context, label: String = "Mesh", geometry: Geometry, material: Material?, visible: Bool = true, renderOrder: Int = 0, renderLayer: RenderLayer = .opaque) {
        self.geometry = geometry
        super.init(context: context, label: label, visible: visible)
        self.material = material
        self.renderOrder = renderOrder
        self.renderLayer = renderLayer
    }

    // MARK: - Decode

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    // MARK: - Deinit

    deinit {
        cleanupGeometrySubscriber()
    }

    // MARK: - Setup

    override open func setup() {
        setupVertexUniforms()
        setupGeometry()
        setupSubmeshes()
        setupMaterial()
    }

    func cleanupGeometrySubscriber() {
        geometrySubscription?.cancel()
        geometrySubscription = nil
    }

    // MARK: - Setup Uniforms

    open func setupVertexUniforms() {
        guard vertexUniforms(for: context.id) == nil else { return }
        ensureVertexUniformBuffer(context: context)
    }

    open func getVertexUniformBuffer(renderContext: Context) -> VertexUniformBuffer? {
        vertexUniforms(for: renderContext.id)
    }

    open func setupGeometry() {
        if geometry == nil {
            geometry = Geometry(context: context)
        }
        // A geometry swapped in under an existing material (as Fabric's Mesh node does) must
        // take effect now as the materials' default vertex layout.
        // The subscription below only sees later changes.
        configureMaterials(for: geometry)
        geometrySubscription = geometry.onUpdate.sink { [weak self] geo in
            guard let self = self else { return }
            self.updateBounds = true
            self.configureMaterials(for: geo)
        }
    }

    /// Gives this mesh's material and every submesh's material the geometry's vertex layout as
    /// their default, so the pipeline they compile first is the one this mesh draws with.
    /// Correctness never depends on it: every draw states its own `DrawLayout`.
    private func configureMaterials(for geometry: Geometry) {
        material?.vertexDescriptor = geometry.vertexDescriptor
        for submesh in submeshes {
            submesh.material?.vertexDescriptor = geometry.vertexDescriptor
        }
    }

    open func setupSubmeshes() {
        for submesh in submeshes {
            assert(submesh.context == context, "Submesh context mismatch")
        }
    }

    open func setupMaterial() {
        guard let material else { return }
        material.vertexDescriptor = geometry.vertexDescriptor
        material.tessellationDescriptor = geometry.tessellationDescriptor
        material.setup()
        material.setMinimumEncodesPerFrame(minimumEncodesPerFrame)

        self.updateAllMaterials()
    }

    // MARK: - Repeated Encoding

    // TODO(render-packets): repeated-encoding stopgap; see Renderable.prepareForRepeatedEncoding.
    override open func prepareForRepeatedEncoding(count: Int) {
        super.prepareForRepeatedEncoding(count: count)
        minimumEncodesPerFrame = max(minimumEncodesPerFrame, max(1, count))
        ensureVertexUniformBuffer(
            context: context,
            encodesPerFrame: max(Satin.maxSubPassesPerFrame, minimumEncodesPerFrame)
        )

        // Expand material uniform buffer to hold one slot per in-flight iteration.
        material?.setMinimumEncodesPerFrame(minimumEncodesPerFrame)
        for submesh in submeshes {
            submesh.material?.setMinimumEncodesPerFrame(minimumEncodesPerFrame)
        }

        // Geometry records one draw state per encode and uploads changed buffers into versioned slots.
        geometry.setMinimumEncodesPerFrame(minimumEncodesPerFrame)
    }

    override open func captureRepeatedEncodingState(iteration: Int, count: Int) {
        super.captureRepeatedEncodingState(iteration: iteration, count: count)
        // Submesh geometries hold only indices: no palette to capture.
        geometry.captureRepeatedEncoding(iteration: iteration, count: count)
    }

    override open func selectRepeatedEncodingSlot(iteration: Int, count: Int) {
        selectRepeatedEncodingState(iteration: iteration, count: count)
    }

    override open func selectRepeatedEncodingState(iteration: Int, count: Int) {
        super.selectRepeatedEncodingState(iteration: iteration, count: count)
        geometry.selectRecentSlot(iteration: iteration, count: count)
        material?.uniforms?.selectRecentSlot(iteration: iteration, count: count)

        for submesh in submeshes {
            submesh.geometry.selectRecentSlot(iteration: iteration, count: count)
            submesh.material?.uniforms?.selectRecentSlot(iteration: iteration, count: count)
        }
    }

    // MARK: - Binding

    /// Records this mesh's vertex uniforms for the context, at the stages its materials read them.
    /// Binds this mesh's vertex uniforms to the stages `material`'s shader reads them in, for the
    /// draw that material is about to record. Repeat bindings across submeshes are skipped when
    /// the draw replays.
    func recordVertexUniforms(in context: RenderableDrawContext, for material: Material) {
        guard let shader = material.shader else { return }
        let vertexWantsVertexUniforms = shader.vertexWantsVertexUniforms
        let fragmentWantsVertexUniforms = shader.fragmentWantsVertexUniforms
        guard vertexWantsVertexUniforms || fragmentWantsVertexUniforms,
              let vertexUniforms = self.vertexUniforms(for: context.renderContext.id)
        else { return }
        if vertexWantsVertexUniforms {
            context.setVertexBuffer(vertexUniforms.buffer, offset: vertexUniforms.offset, index: .VertexUniforms)
        }
        if fragmentWantsVertexUniforms {
            context.setFragmentBuffer(vertexUniforms.buffer, offset: vertexUniforms.offset, index: .VertexUniforms)
        }
    }

    // MARK: - Update

    override open func update() {
        geometry.update()
        // A pose change moves a skinned mesh's bounds without any geometry update.
        if geometry.isSkinned, let jointPalette = geometry.jointPalette,
           jointPalette !== boundsJointPalette || jointPalette.poseVersion != boundsPoseVersion {
            boundsJointPalette = jointPalette
            boundsPoseVersion = jointPalette.poseVersion
            updateBounds = true
        }
        material?.update()
        for submesh in submeshes {
            submesh.update()
        }
        super.update()
    }

    override open func encode(_ commandBuffer: MTLCommandBuffer) {
        geometry.encode(commandBuffer)
        material?.encode(commandBuffer)
        for submesh in submeshes {
            submesh.encode(commandBuffer)
        }
        super.encode(commandBuffer)
    }

    override open func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int) {
        vertexUniforms(for: renderContext.id)?.update(
            object: self,
            camera: camera,
            viewport: viewport,
            index: index
        )

        super.update(
            renderContext: renderContext,
            camera: camera,
            viewport: viewport,
            index: index
        )
    }
    
    private func updateAllMaterials()
    {
        var allMaterials = [Material]()
        if let material = material {
            allMaterials.append(material)
        }
        for submesh in submeshes {
            if let material = submesh.material {
                allMaterials.append(material)
            }
        }
        
        self.materials = allMaterials
    }

    // MARK: - Draw

    override open func draw(in context: RenderableDrawContext) {
        drawMesh(in: context, instanceCount: instanceCount)
    }

    /// Records this mesh's draw with `instanceCount` instances: its vertex uniforms and geometry
    /// bindings, then the material and draw call of each submesh drawn in this pass, or its own.
    func drawMesh(in context: RenderableDrawContext, instanceCount: Int) {
        let shadow = context.isShadowPass
        let geometryContext = context.geometryContext(instanceCount: instanceCount)
        geometry.recordBindings(in: geometryContext)

        if !submeshes.isEmpty {
            let layout = drawLayout
            for submesh in submeshes where submesh.visible {
                guard let submeshMaterial = submesh.material,
                      materialMatchesCurrentPass(submeshMaterial, shadow: shadow)
                else { continue }
                recordVertexUniforms(in: context, for: submeshMaterial)
                submesh.draw(in: context, instanceCount: instanceCount, layout: layout)
            }
        } else if let material, materialMatchesCurrentPass(material, shadow: shadow) {
            recordVertexUniforms(in: context, for: material)
            // The material may be shared with meshes of another layout: pick the pipeline for ours.
            material.draw(in: context.materialContext(layout: drawLayout))
            geometry.recordDrawCall(in: geometryContext)
        }
    }

    private func materialMatchesCurrentPass(_ material: Material?, shadow: Bool) -> Bool {
        guard let material else { return false }
        if shadow {
            return true
        }

        let isTransparent = material.blending != .disabled

        switch materialPass {
        case .all:
            return true
        case .opaque:
            return !isTransparent
        case .alphaTransparent:
            return material.blending == .alpha
        case .classicTransparent:
            return isTransparent
        case .surfaceOpaque:
            return material.lightingModel == .surface && !isTransparent
        case .unlitOpaque:
            return material.lightingModel == .unlit && !isTransparent
        }
    }

    open func addSubmesh(_ submesh: Submesh) {
        assert(submesh.context == context, "Submesh context mismatch")
        submeshes.append(submesh)
        // Its material needs its depth-stencil state and shader before the first draw; nothing
        // else sets a submesh up.
        submesh.setup(vertexGeometry: geometry)
    }

    // MARK: - Comoute Bounds

    override open func computeBounds() -> Bounds {
        geometry.bounds
    }

    override open func computeLocalBounds() -> Bounds {
        transformBounds(bounds, localMatrix)
    }

    override open func computeWorldBounds() -> Bounds {
        var result = transformBounds(bounds, worldMatrix)
        for child in children {
            result = mergeBounds(result, child.worldBounds)
        }
        return result
    }

    // MARK: - Intersect

    override open func intersect(
        ray: Ray,
        intersections: inout [RaycastResult],
        options: RaycastOptions
    ) -> Bool {
        guard visible || options.invisible, intersects(ray: ray) else { return false }

        var geometryIntersections = [IntersectionResult]()
        geometry.intersect(
            ray: worldMatrixInverse.act(ray),
            intersections: &geometryIntersections
        )
        geometryIntersections.sort { $0.distance < $1.distance }

        var results = [RaycastResult]()
        for geometryIntersection in geometryIntersections {
            let hitPosition = simd_make_float3(
                worldMatrix * simd_make_float4(geometryIntersection.position, 1.0)
            )

            let raycastResult = RaycastResult(
                barycentricCoordinates: geometryIntersection.barycentricCoordinates,
                distance: simd_length(hitPosition - ray.origin),
                normal: normalMatrix * geometryIntersection.normal,
                position: hitPosition,
                primitiveIndex: geometryIntersection.primitiveIndex,
                object: self,
                submesh: nil
            )

            if options.first {
                intersections.append(raycastResult)
                return true
            } else {
                results.append(raycastResult)
            }
        }

        intersections.append(contentsOf: results)

        if options.recursive {
            for child in children {
                if child.intersect(
                    ray: ray,
                    intersections: &intersections,
                    options: options
                ) && options.first {
                    return true
                }
            }
        }

        return results.count > 0
    }
}
