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

    // `drawLayout` is read for every draw; it is rebuilt only when its inputs change. A geometry replaces its vertex descriptor whenever its attributes change,
    // so comparing the geometry, its descriptor and its palette by identity is enough.
    private var cachedDrawLayout: DrawLayout?
    private var cachedDrawLayoutGeometry: Geometry?
    private var cachedDrawLayoutJointPalette: JointPalette?

    public let instanceCountPublisher = PassthroughSubject<Int, Never>()
    public var instanceCount = 1 {
        didSet {
            instanceCountPublisher.send(instanceCount)
        }
    }


    open var geometry: Geometry {
        didSet {
            if geometry != oldValue {
                setupGeometry()
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
    // Strong: it is the palette in use, replaced when the geometry's changes; no side table.
    private var boundsJointPalette: JointPalette?
    private var boundsObserver: MeshBoundsObserver?

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

    /// A decoded mesh starts with an empty geometry; its setup gives it the mesh's context.
    public required init(from decoder: Decoder) throws {
        geometry = Geometry(context: try decoder.requireSatinContext(typeName: String(describing: Self.self)))
        try super.init(from: decoder)
    }

    // MARK: - Deinit

    deinit {
        if let boundsObserver {
            boundsJointPalette?.removeBoundsObserver(boundsObserver)
            boundsObserver.mesh = nil
        }
        cleanupGeometrySubscriber()
    }

    // MARK: - Setup

    override open func setup() {
        setupGeometry()
        setupSubmeshes()
        setupMaterial()
    }

    func cleanupGeometrySubscriber() {
        geometrySubscription?.cancel()
        geometrySubscription = nil
    }

    open func setupGeometry() {
        // A geometry swapped in under an existing material (as Fabric's Mesh node does) must
        // take effect now as the materials' default vertex layout.
        // The subscription below only sees later changes.
        configureMaterials(for: geometry)
        observeBoundsPalette()
        // Unowned: the subscription is this object's own, cancelled before it goes, and an unowned
        // capture needs no side table on an object every frame retains.
        geometrySubscription = geometry.onUpdate.sink { [unowned self] geo in
            self.observeBoundsPalette()
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

        self.updateAllMaterials()
    }

    // MARK: - Binding

    /// Binds the render event's vertex uniforms to the stages `material`'s shader reads them in.
    /// Called after the material records, so its pipeline, and with it which stages read them, is
    /// known. Repeat bindings across submeshes are skipped when the draws encode.
    func recordVertexUniforms(in context: RenderableDrawContext, for material: Material) {
        guard let shader = material.shader else { return }
        let vertexUniforms = context.vertexUniforms
        let usage = context.storage.recordingPipelineUsage
        if shader.vertexWantsVertexUniforms || (usage?.vertex.buffers.contains(VertexBufferIndex.VertexUniforms.rawValue) ?? true) {
            context.setVertexBuffer(vertexUniforms.buffer, offset: vertexUniforms.offset, index: .VertexUniforms)
        }
        if shader.fragmentWantsVertexUniforms || (usage?.fragment.buffers.contains(FragmentBufferIndex.VertexUniforms.rawValue) ?? true) {
            context.setFragmentBuffer(vertexUniforms.buffer, offset: vertexUniforms.offset, index: .VertexUniforms)
        }
    }

    // MARK: - Update

    override open func update() {
        geometry.update()
        observeBoundsPalette()
        material?.update()
        for submesh in submeshes {
            submesh.update()
        }
        super.update()
    }

    /// Follow palette replacement as well as its pose changes. Ordinary meshes allocate no relay.
    private func observeBoundsPalette() {
        let palette = geometry.boundsPaletteDependency
        guard palette !== boundsJointPalette else { return }
        if let boundsObserver {
            boundsJointPalette?.removeBoundsObserver(boundsObserver)
        }
        boundsJointPalette = palette
        if let palette {
            let observer = boundsObserver ?? MeshBoundsObserver(mesh: self)
            boundsObserver = observer
            palette.addBoundsObserver(observer)
        }
        updateBounds = true
    }

    override open func encode(in context: EncodingContext) {
        geometry.encode(in: context)
        material?.encode(in: context)
        for submesh in submeshes {
            submesh.encode(in: context)
        }
        super.encode(in: context)
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

    /// Records this mesh's draws with `instanceCount` instances: for each submesh drawn in this
    /// pass, or for itself, its material, vertex uniforms, then its geometry's `draw(in:)` (over the
    /// submesh's indices for a submesh). Nothing to draw records nothing.
    func drawMesh(in context: RenderableDrawContext, instanceCount: Int) {
        // Read once for the whole draw: a class property read is a checked access each time.
        let geometry = self.geometry
        guard instanceCount > 0, geometry.hasVertexBuffers else { return }

        // The material may be shared with meshes of another layout: pick the pipeline for ours.
        let layout = drawLayout
        if !submeshes.isEmpty {
            for submesh in submeshes where submesh.visible {
                guard let submeshMaterial = submesh.material,
                      materialMatchesCurrentPass(submeshMaterial, in: context)
                else { continue }
                submeshMaterial.draw(in: context.materialContext(layout: layout))
                recordVertexUniforms(in: context, for: submeshMaterial)
                geometry.draw(in: context.geometryContext(instanceCount: instanceCount, indexBufferOffset: submesh.indexBufferOffset, elements: submesh.geometry))
            }
        } else if let material, materialMatchesCurrentPass(material, in: context) {
            material.draw(in: context.materialContext(layout: layout))
            recordVertexUniforms(in: context, for: material)
            geometry.draw(in: context.geometryContext(instanceCount: instanceCount))
        }
    }

    /// A mesh whose submeshes carry the materials asks them: any visible submesh blending in
    /// `materialPass` orders the whole recording. Opaque submeshes in the same pass are then drawn
    /// as two culled halves, the same pixels as one uncullled draw.
    override func drawsTransparent(in materialPass: MaterialPass) -> Bool {
        guard !submeshes.isEmpty else { return super.drawsTransparent(in: materialPass) }
        for submesh in submeshes where submesh.visible {
            if let material = submesh.material, material.blending != .disabled, materialPass.includes(material) {
                return true
            }
        }
        return false
    }

    private func materialMatchesCurrentPass(_ material: Material, in context: RenderableDrawContext) -> Bool {
        context.isShadowPass || context.materialPass.includes(material)
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

/// A palette's bounds notification reaches a mesh without keeping it alive or adding a weak
/// reference to it. The mesh unregisters and clears the relay before its stored properties go.
final class MeshBoundsObserver {
    unowned var mesh: Mesh?

    init(mesh: Mesh) {
        self.mesh = mesh
    }
}
