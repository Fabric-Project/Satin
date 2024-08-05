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

open class Mesh: Object, Renderable {
    public var opaque: Bool { material!.blending == .disabled }

    public let doubleSidedPublisher = PassthroughSubject<Bool, Never>()
    public var doubleSided: Bool = false {
        didSet {
            doubleSidedPublisher.send(doubleSided)
        }
    }

    public let renderOrderPublisher = PassthroughSubject<Int, Never>()
    public var renderOrder = 0 {
        didSet {
            renderOrderPublisher.send(renderOrder)
        }
    }

    public let renderPassPublisher = PassthroughSubject<Int, Never>()
    public var renderPass = 0 {
        didSet {
            renderPassPublisher.send(renderPass)
        }
    }

    public var lighting: Bool { material?.lighting ?? false }

    public let receiveShadowPublisher = PassthroughSubject<Bool, Never>()
    public var receiveShadow = false {
        didSet {
            if receiveShadow != oldValue {
                material?.receiveShadow = receiveShadow
                for submesh in submeshes {
                    submesh.material?.receiveShadow = receiveShadow
                }
            }
            receiveShadowPublisher.send(receiveShadow)
        }
    }

    public let castShadowPublisher = PassthroughSubject<Bool, Never>()
    public var castShadow = false {
        didSet {
            if castShadow != oldValue {
                material?.castShadow = castShadow
                for submesh in submeshes {
                    submesh.material?.castShadow = castShadow
                }
            }
            castShadowPublisher.send(castShadow)
        }
    }

    public let cullModePublisher = PassthroughSubject<MTLCullMode, Never>()
    public var cullMode: MTLCullMode = .back {
        didSet {
            cullModePublisher.send(cullMode)
        }
    }

    public let triangleFillModePublisher = PassthroughSubject<MTLTriangleFillMode, Never>()
    public var triangleFillMode: MTLTriangleFillMode = .fill {
        didSet {
            triangleFillModePublisher.send(triangleFillMode)
        }
    }

    public var windingOrder: MTLWinding {
        get {
            geometry.windingOrder
        }
        set {
            geometry.windingOrder = newValue
        }
    }

    open func isDrawable(renderContext: Context, shadow: Bool) -> Bool {
        guard instanceCount > 0,
              !geometry.vertexBuffers.isEmpty,
              vertexUniforms[renderContext] != nil
        else { return false }

        if submeshes.isEmpty, let material = material, material.getPipeline(renderContext: renderContext, shadow: shadow) != nil {
            return true
        } else if let submesh = submeshes.first, let material = submesh.material, material.getPipeline(renderContext: renderContext, shadow: false) != nil {
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

    public var vertexUniforms: [Context: VertexUniformBuffer] = [:]

    public var preDraw: ((_ renderEncoder: MTLRenderCommandEncoder) -> Void)?

    open var geometry = Geometry() {
        didSet {
            if geometry != oldValue {
                setupGeometry()
                _updateLocalBounds = true
            }
        }
    }

    open var material: Material? {
        didSet {
            if material != oldValue {
                material?.vertexDescriptor = geometry.vertexDescriptor
                setupMaterial()
            }
        }
    }

    open var materials: [Material] {
        var allMaterials = [Material]()
        if let material = material {
            allMaterials.append(material)
        }
        for submesh in submeshes {
            if let material = submesh.material {
                allMaterials.append(material)
            }
        }
        return allMaterials
    }

    internal var geometrySubscription: AnyCancellable?

    public internal(set) var submeshes: [Submesh] = []

    public init(label: String = "Mesh", geometry: Geometry, material: Material?, visible: Bool = true, renderOrder: Int = 0, renderPass: Int = 0) {
        self.geometry = geometry
        self.material = material
        self.renderOrder = renderOrder
        self.renderPass = renderPass
        super.init(label: label, visible: visible)
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

    internal func cleanupGeometrySubscriber() {
        geometrySubscription?.cancel()
        geometrySubscription = nil
    }

    // MARK: - Setup Uniforms

    open func setupVertexUniforms() {
        guard let context = context, vertexUniforms[context] == nil else { return }
        vertexUniforms[context] = VertexUniformBuffer(context: context)
    }

    open func getVertexUniformBuffer(renderContext: Context) -> VertexUniformBuffer? {
        vertexUniforms[renderContext]
    }

    open func setupGeometry() {
        guard let context = context else { return }
        geometrySubscription = geometry.onUpdate.sink { [weak self] geo in
            guard let self = self else { return }
            self.updateBounds = true
            self.material?.vertexDescriptor = geo.vertexDescriptor
        }
        geometry.context = context
    }

    open func setupSubmeshes() {
        guard let context = context else { return }
        for submesh in submeshes { submesh.context = context }
    }

    open func setupMaterial() {
        guard let context = context, let material = material else { return }
        material.vertexDescriptor = geometry.vertexDescriptor
        material.context = context
    }

    // MARK: - Binding

    open func bind(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        bindUniforms(renderContext: renderContext, renderEncoderState: renderEncoderState)
        bindGeometry(renderEncoderState: renderEncoderState, shadow: shadow)
    }

    open func bindUniforms(renderContext: Context, renderEncoderState: RenderEncoderState) {
        guard let shader = material?.shader else { return }
        if shader.vertexWantsVertexUniforms {
            renderEncoderState.vertexVertexUniforms = vertexUniforms[renderContext]
        }
        if shader.fragmentWantsVertexUniforms {
            renderEncoderState.fragmentVertexUniforms = vertexUniforms[renderContext]
        }
    }

    open func bindGeometry(renderEncoderState: RenderEncoderState, shadow: Bool) {
        geometry.bind(renderEncoderState: renderEncoderState, shadow: shadow)
    }

    // MARK: - Update

    override open func update() {
        geometry.update()
        material?.update()
        for submesh in submeshes { submesh.update() }
        super.update()
    }

    override open func encode(_ commandBuffer: MTLCommandBuffer) {
        geometry.encode(commandBuffer)
        material?.encode(commandBuffer)
        for submesh in submeshes { submesh.encode(commandBuffer) }
        super.encode(commandBuffer)
    }

    override open func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int) {
        vertexUniforms[renderContext]?.update(object: self, camera: camera, viewport: viewport, index: index)

        super.update(
            renderContext: renderContext,
            camera: camera,
            viewport: viewport,
            index: index
        )
    }

    // MARK: - Draw

    open func draw(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
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
            for submesh in submeshes where submesh.visible {
                submesh.draw(
                    renderContext: renderContext,
                    renderEncoderState: renderEncoderState,
                    instanceCount: instanceCount,
                    shadow: shadow
                )
            }
        } else {
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

    open func addSubmesh(_ submesh: Submesh) {
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

    override open func intersect(ray: Ray, intersections: inout [RaycastResult], recursive: Bool = true, invisible: Bool = false) {
        guard visible || invisible, intersects(ray: ray) else { return }

        var geometryIntersections = [IntersectionResult]()
        geometry.intersect(
            ray: worldMatrixInverse.act(ray),
            intersections: &geometryIntersections
        )

        var results = [RaycastResult]()
        for geometryIntersection in geometryIntersections {
            let hitPosition = simd_make_float3(
                worldMatrix * simd_make_float4(geometryIntersection.position, 1.0)
            )

            /*
             let v0 = getVertex(index: triangle.i0)
             let v1 = getVertex(index: triangle.i1)
             let v2 = getVertex(index: triangle.i2)

             uv: v0.uv * bc.x + v1.uv * bc.y + v2.uv * bc.z,
             */

            results.append(
                RaycastResult(
                    barycentricCoordinates: geometryIntersection.barycentricCoordinates,
                    distance: simd_length(hitPosition - ray.origin),
                    normal: normalMatrix * geometryIntersection.normal,
                    position: hitPosition,
                    primitiveIndex: geometryIntersection.primitiveIndex,
                    object: self,
                    submesh: nil
                )
            )
        }

        intersections.append(contentsOf: results)

        if recursive {
            for child in children {
                child.intersect(
                    ray: ray,
                    intersections: &intersections,
                    recursive: recursive,
                    invisible: invisible
                )
            }
        }
    }
}
