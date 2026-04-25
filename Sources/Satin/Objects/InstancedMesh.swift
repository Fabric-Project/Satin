//
//  InstancedMesh.swift
//  Satin
//
//  Created by Reza Ali on 10/19/22.
//

import Combine
import Foundation
import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public class InstancedMesh: Mesh {
    override public func isDrawable(renderContext: Context, shadow: Bool) -> Bool {
        guard instanceMatrixBuffer != nil, instanceMatricesUniforms.count >= instanceCount else { return false }

        if let drawCount = drawCount {
            if drawCount > 0 {
                return super.isDrawable(renderContext: renderContext, shadow: shadow)
            }
            else {
                return false
            }
        }
        else {
            return super.isDrawable(renderContext: renderContext, shadow: shadow)
        }
    }

    public var drawCount: Int? {
        didSet {
            if let drawCount = drawCount, drawCount > instanceCount {
                instanceCount = drawCount
                print("maxed out instances, adding more: \(instanceCount)")
            }
        }
    }

    override public var instanceCount: Int {
        didSet {
            if instanceCount != oldValue {
                instanceMatrices.reserveCapacity(instanceCount)
                instanceMatricesUniforms.reserveCapacity(instanceCount)
                while instanceMatrices.count < instanceCount {
                    instanceMatrices.append(matrix_identity_float4x4)
                    instanceMatricesUniforms.append(InstanceMatrixUniforms(modelMatrix: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3))
                }
                _setupInstanceMatrixBuffer = true
            }
        }
    }

    var instanceMatrices: [simd_float4x4]
    var instanceMatricesUniforms: [InstanceMatrixUniforms]

    private var transformSubscriber: AnyCancellable?
    private var _updateInstanceMatricesUniforms = true
    private var _setupInstanceMatrixBuffer = true
    private var _updateInstanceMatrixBuffer = true
    private var instanceMatrixBuffer: InstanceMatrixUniformBuffer?

    override public var material: Material? {
        didSet {
            material?.instancing = true
        }
    }

    public init(label: String = "Instanced Mesh", geometry: Geometry, material: Material?, count: Int) {
        material?.instancing = true

        instanceMatricesUniforms = .init(repeating: InstanceMatrixUniforms(modelMatrix: matrix_identity_float4x4, normalMatrix: matrix_identity_float3x3), count: count)

        instanceMatrices = .init(repeating: matrix_identity_float4x4, count: count)

        super.init(label: label, geometry: geometry, material: material)

        instanceCount = count

        transformSubscriber = transformPublisher.sink { [weak self] _ in
            self?._updateInstanceMatricesUniforms = true
        }
    }

    public required init(from _: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
    
    public func setInstanceMatrices(_ matrices: [simd_float4x4]) {
        
        self.instanceCount = matrices.count
        self.instanceMatrices = matrices
        
        self.updateInstanceMatricesUniforms()
        
        _updateInstanceMatrixBuffer = true

    }
    

    public func setMatrixAt(index: Int, matrix: matrix_float4x4) {
        guard index < instanceCount else { return }
        instanceMatrices[index] = matrix
        instanceMatricesUniforms[index].modelMatrix = simd_mul(worldMatrix, matrix)
        let n = instanceMatricesUniforms[index].modelMatrix.inverse.transpose
        instanceMatricesUniforms[index].normalMatrix = simd_float3x3(
            simd_make_float3(n.columns.0),
            simd_make_float3(n.columns.1),
            simd_make_float3(n.columns.2)
        )

        _updateInstanceMatrixBuffer = true
    }

    // MARK: - Instancing

    public func getMatrixAt(index: Int) -> matrix_float4x4 {
        guard index < instanceCount else { fatalError("Unable to get matrix at \(index)") }
        return instanceMatrices[index]
    }

    public func getWorldMatrixAt(index: Int) -> matrix_float4x4 {
        guard index < instanceCount else { fatalError("Unable to get world matrix at \(index)") }
        return instanceMatricesUniforms[index].modelMatrix
    }

    override public func setup() {
        super.setup()
        setupInstanceBuffer()
    }

    override public func update() {
        if _updateInstanceMatricesUniforms { updateInstanceMatricesUniforms() }
        if _setupInstanceMatrixBuffer { setupInstanceBuffer() }
        if _updateInstanceMatrixBuffer { updateInstanceBuffer() }
        super.update()
    }

    override public func bind(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        super.bind(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )
        renderEncoderState.vertexInstanceUniforms = instanceMatrixBuffer
    }

    // MARK: - Private Instancing

    func setupInstanceBuffer() {
        guard let context, instanceCount > 0 else { return }
        instanceMatrixBuffer = InstanceMatrixUniformBuffer(device: context.device, count: instanceCount)
        _setupInstanceMatrixBuffer = false
        _updateInstanceMatrixBuffer = true
    }

    func updateInstanceBuffer() {
        instanceMatrixBuffer?.update(data: instanceMatricesUniforms)
        _updateInstanceMatrixBuffer = false
    }

    @inline(__always)
    private func normalMatrix(from modelMatrix: simd_float4x4) -> simd_float3x3 {
        let c0 = simd_make_float3(modelMatrix.columns.0)
        let c1 = simd_make_float3(modelMatrix.columns.1)
        let c2 = simd_make_float3(modelMatrix.columns.2)

        let m3 = simd_float3x3(c0, c1, c2)
        return simd_transpose(simd_inverse(m3))
    }
    
    func updateInstanceMatricesUniforms() {

        let count = instanceCount
        guard count > 0 else {
            _updateInstanceMatricesUniforms = false
            _updateInstanceMatrixBuffer = true
            return
        }

        let cores = ProcessInfo.processInfo.processorCount
        let iterations = min(count, max(1, cores))        // docs guidance + cap to work
        let chunkSize = (count + iterations - 1) / iterations  // ceil-div
        let w = self.worldMatrix
        
        self.instanceMatrices.withUnsafeBufferPointer { src in
            self.instanceMatricesUniforms.withUnsafeMutableBufferPointer { dst in
                
                DispatchQueue.concurrentPerform(iterations: iterations) { iter in
                    let start = iter * chunkSize
                    if start >= count { return }
                    let end = min(start + chunkSize, count)
                    
                    var i = start
                    let unroll = 4
                    let limit = end - ((end - start) % unroll)
                    
                    while i < limit
                    {
                        let m0 = simd_mul(w, src[i    ]); dst[i    ].modelMatrix = m0; dst[i    ].normalMatrix = normalMatrix(from: m0)
                        let m1 = simd_mul(w, src[i + 1]); dst[i + 1].modelMatrix = m1; dst[i + 1].normalMatrix = normalMatrix(from: m1)
                        let m2 = simd_mul(w, src[i + 2]); dst[i + 2].modelMatrix = m2; dst[i + 2].normalMatrix = normalMatrix(from: m2)
                        let m3 = simd_mul(w, src[i + 3]); dst[i + 3].modelMatrix = m3; dst[i + 3].normalMatrix = normalMatrix(from: m3)
                        i += 4
                    }
                    
                    while i < end
                    {
                        let m = simd_mul(w, src[i])
                        dst[i].modelMatrix = m
                        dst[i].normalMatrix = normalMatrix(from: m)
                        i += 1
                    }
                }
            }
        }

        _updateInstanceMatricesUniforms = false
        _updateInstanceMatrixBuffer = true
    }

    
//    func updateInstanceMatricesUniforms() {
//        
//        // Simple thread safe array access
//        let threadCount = ProcessInfo.processInfo.processorCount * 3
//        let offset = instanceCount / threadCount
//        
//        DispatchQueue.concurrentPerform(iterations: threadCount, execute: { threadCount in
//            
//            for i in 0 ..< offset
//            {
//                let matrix = simd_mul(worldMatrix, instanceMatrices[i])
//                let n = matrix.inverse.transpose
//                
//                instanceMatricesUniforms[i].modelMatrix = matrix
//                instanceMatricesUniforms[i].normalMatrix = simd_float3x3(
//                    simd_make_float3(n.columns.0),
//                    simd_make_float3(n.columns.1),
//                    simd_make_float3(n.columns.2)
//                )
//            }
//            
//          
//        })
//        
//        _updateInstanceMatricesUniforms = false
//        _updateInstanceMatrixBuffer = true
//    }

//    
//    @inline(__always)
//    private func normalMatrix(from modelMatrix: simd_float4x4) -> simd_float3x3 {
//        let c0 = simd_make_float3(modelMatrix.columns.0)
//        let c1 = simd_make_float3(modelMatrix.columns.1)
//        let c2 = simd_make_float3(modelMatrix.columns.2)
//
//        let m3 = simd_float3x3(c0, c1, c2)
//        return simd_transpose(simd_inverse(m3))
//    }
//    
//    func updateInstanceMatricesUniforms()
//    {
//        let count = instanceCount
//        let w = worldMatrix
//
//        instanceMatrices.withUnsafeBufferPointer { src in
//            instanceMatricesUniforms.withUnsafeMutableBufferPointer { dst in
//                // If you really need parallelism, prefer chunking (see below).
//                var i = 0
//                let unroll = 4
//                let limit = count - (count % unroll)
//
//                // 4× unrolled
//                while i < limit {
//                    @inline(__always) func process(_ j: Int) {
//                        let model = simd_mul(w, src[j])
//                        dst[j].modelMatrix = model
//                        dst[j].normalMatrix = normalMatrix(from: model)
//                    }
//
//                    process(i)
//                    process(i + 1)
//                    process(i + 2)
//                    process(i + 3)
//                    i += unroll
//                }
//
//                // tail
//                while i < count {
//                    let model = simd_mul(w, src[i])
//                    dst[i].modelMatrix = model
//                    dst[i].normalMatrix = normalMatrix(from: model)
//                    i += 1
//                }
//            }
//        }
//
//        _updateInstanceMatricesUniforms = false
//        _updateInstanceMatrixBuffer = true
//    }

    
    override public func draw(renderContext: Context, renderEncoderState: RenderEncoderState, instanceCount: Int, shadow: Bool) {
        if let drawCount = drawCount {
            super.draw(
                renderContext: renderContext,
                renderEncoderState: renderEncoderState,
                instanceCount: min(drawCount, instanceCount),
                shadow: shadow
            )
        }
        else {
            super.draw(
                renderContext: renderContext,
                renderEncoderState: renderEncoderState,
                instanceCount: instanceCount,
                shadow: shadow
            )
        }
    }

    // MARK: - Intersections

    override public func computeLocalBounds() -> Bounds {
        var result = createBounds()
        for i in 0 ..< instanceCount {
            result = mergeBounds(result, transformBounds(bounds, getMatrixAt(index: i)))
        }
        return result
    }

    override public func computeWorldBounds() -> Bounds {
        var result = createBounds()
        for i in 0 ..< instanceCount {
            result = transformBounds(bounds, getWorldMatrixAt(index: i))
        }

        for child in children {
            result = mergeBounds(result, child.worldBounds)
        }
        return result
    }

    override public func intersects(ray: Ray) -> Bool {
        for i in 0 ..< instanceCount {
            if rayBoundsIntersect(getWorldMatrixAt(index: i).inverse.act(ray), bounds) {
                return true
            }
        }
        return false
    }

    override open func intersect(
        ray: Ray,
        intersections: inout [RaycastResult],
        options: RaycastOptions
    ) -> Bool {
        guard visible || options.invisible, intersects(ray: ray) else { return false }

        var geometryIntersections = [IntersectionResult]()

        var instanceIntersections = [Int]()
        for i in 0 ..< instanceCount {
            let preCount = geometryIntersections.count
            geometry.intersect(
                ray: getWorldMatrixAt(index: i).inverse.act(ray),
                intersections: &geometryIntersections
            )
            let postCount = geometryIntersections.count

            for i in preCount ..< postCount {
                instanceIntersections.append(i)
            }
        }

        var results = [RaycastResult]()
        for (instance, intersection) in zip(instanceIntersections, geometryIntersections) {
            let raycastResult = RaycastResult(
                barycentricCoordinates: intersection.barycentricCoordinates,
                distance: intersection.distance,
                normal: intersection.normal,
                position: simd_make_float3(getWorldMatrixAt(index: instance) * simd_make_float4(intersection.position, 1.0)),
                primitiveIndex: intersection.primitiveIndex,
                object: self,
                submesh: nil,
                instance: instance
            )

            if options.first {
                intersections.append(raycastResult)
                return true
            }
            else {
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

    // MARK: - Deinit

    deinit {
        transformSubscriber?.cancel()
    }
}
