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

open class Mesh: Renderable {

    override public var receiveShadow: Bool {
        didSet {
            if receiveShadow != oldValue {
                material?.receiveShadow = receiveShadow
                for submesh in submeshes {
                    submesh.material?.receiveShadow = receiveShadow
                }
            }
        }
    }
  
    override public var castShadow:Bool {
        didSet {
            if castShadow != oldValue {
                material?.castShadow = castShadow
                for submesh in submeshes {
                    submesh.material?.castShadow = castShadow
                }
            }
        }
    }

    override public var windingOrder: MTLWinding {
        get {
            geometry.windingOrder
        }
        set {
            geometry.windingOrder = newValue
        }
    }

    override open func isDrawable(renderContext: Context, shadow: Bool) -> Bool {
        guard instanceCount > 0,
              !geometry.vertexBuffers.isEmpty,
              vertexUniforms[renderContext.id] != nil
        else { return false }

        if submeshes.isEmpty,
           let material = material,
           materialMatchesCurrentPass(material, shadow: shadow),
           material.getPipeline(renderContext: renderContext, shadow: shadow) != nil
        {
            return true
        } else if submeshes.contains(where: {
            $0.visible &&
                materialMatchesCurrentPass($0.material, shadow: shadow) &&
                $0.material?.getPipeline(renderContext: renderContext, shadow: shadow) != nil
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
                geometry.setMinimumSlotCount(minimumRepeatedEncodingCount)
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
    private var minimumRepeatedEncodingCount = 1

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
        guard vertexUniforms[context.id] == nil else { return }
        vertexUniforms[context.id] = VertexUniformBuffer(context: context)
    }

    open func getVertexUniformBuffer(renderContext: Context) -> VertexUniformBuffer? {
        vertexUniforms[renderContext.id]
    }

    open func setupGeometry() {
        if geometry == nil {
            geometry = Geometry(context: context)
        }
        geometrySubscription = geometry.onUpdate.sink { [weak self] geo in
            guard let self = self else { return }
            self.updateBounds = true
            self.material?.vertexDescriptor = geo.vertexDescriptor
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
        material.setMinimumSlotCount(minimumRepeatedEncodingCount)

        self.updateAllMaterials()
    }

    // MARK: - Repeated Encoding

    override open func prepareForRepeatedEncoding(count: Int) {
        minimumRepeatedEncodingCount = max(minimumRepeatedEncodingCount, max(1, count))
        // Build a sizing context with iterationsPerFrame = count so VertexUniformBuffer
        // allocates maxBuffersInFlight × max(maxSubPassesPerFrame, count) slots.
        // Store under the original context.id so bindUniforms finds it without
        // changing the renderContext passed by SubgraphIteratorRenderable.
        vertexUniforms[context.id] = VertexUniformBuffer(context: context.with(iterationsPerFrame: minimumRepeatedEncodingCount))

        // Expand material uniform buffer to hold one slot per in-flight iteration.
        material?.setMinimumSlotCount(minimumRepeatedEncodingCount)
        for submesh in submeshes {
            submesh.material?.setMinimumSlotCount(minimumRepeatedEncodingCount)
        }

        // Static geometry ignores this. Dynamic geometry uploads directly into versioned slots.
        geometry.setMinimumSlotCount(minimumRepeatedEncodingCount)
    }

    override open func selectRepeatedEncodingSlot(iteration: Int, count: Int) {
        geometry.selectRecentSlot(iteration: iteration, count: count)
        material?.uniforms?.selectRecentSlot(iteration: iteration, count: count)

        for submesh in submeshes {
            submesh.geometry.selectRecentSlot(iteration: iteration, count: count)
            submesh.material?.uniforms?.selectRecentSlot(iteration: iteration, count: count)
        }
    }

    // MARK: - Binding

    open func bind(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        bindUniforms(renderContext: renderContext, renderEncoderState: renderEncoderState)
        bindGeometry(renderEncoderState: renderEncoderState, shadow: shadow)
    }

    open func bindUniforms(renderContext: Context, renderEncoderState: RenderEncoderState) {
        guard let shader = material?.shader else { return }
        if shader.vertexWantsVertexUniforms {
            renderEncoderState.vertexVertexUniforms = vertexUniforms[renderContext.id]
        }
        if shader.fragmentWantsVertexUniforms {
            renderEncoderState.fragmentVertexUniforms = vertexUniforms[renderContext.id]
        }
    }

    open func bindGeometry(renderEncoderState: RenderEncoderState, shadow: Bool) {
        geometry.bind(renderEncoderState: renderEncoderState, shadow: shadow)
    }

    // MARK: - Update

    override open func update() {
        geometry.update()
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
        vertexUniforms[renderContext.id]?.update(
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

    override open func draw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        draw(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            instanceCount: instanceCount,
            shadow: shadow
        )
    }

    open func draw(renderContext: Context, renderEncoderState: RenderEncoderState, instanceCount: Int, shadow: Bool) {
        bind(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )

        if !submeshes.isEmpty {
            for submesh in submeshes where submesh.visible && materialMatchesCurrentPass(submesh.material, shadow: shadow) {
                submesh.draw(
                    renderContext: renderContext,
                    renderEncoderState: renderEncoderState,
                    instanceCount: instanceCount,
                    shadow: shadow
                )
            }
        } else if materialMatchesCurrentPass(material, shadow: shadow) {
            material?.bind(
                renderContext: renderContext,
                renderEncoderState: renderEncoderState,
                shadow: shadow
            )
            geometry.draw(
                renderEncoderState: renderEncoderState,
                instanceCount: instanceCount
            )
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
        submesh.parent = self
        submeshes.append(submesh)
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
