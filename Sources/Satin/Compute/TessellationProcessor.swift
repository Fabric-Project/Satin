//
//  TesselationProcessor.swift
//  Satin
//
//  Created by Reza Ali on 4/1/23.
//  Copyright © 2023 Reza Ali. All rights reserved.
//

import Foundation
import Metal

public protocol Tessellator: ComputeProcessor {
    /// The bytes one dispatch writes: a factors value per patch.
    var factorsLength: Int { get }
    /// Where the next dispatch writes its factors, such as a slice of a frame's arena. Nothing is
    /// dispatched without one: the tessellator owns no factors storage.
    var factorsDestination: (buffer: MTLBuffer, offset: Int)? { get set }
    /// Returns true only after work producing the destination's factors was encoded.
    /// No GPU wait is performed. Custom tessellators must report a failed preparation as false.
    func encodeFactors(_ commandBuffer: MTLCommandBuffer, into destination: (buffer: MTLBuffer, offset: Int), iterations: Int) -> Bool
    func update(_ commandBuffer: MTLCommandBuffer, iterations: Int)
    func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int)
}

open class TessellationProcessor<T>: ComputeProcessor, Tessellator {
    override var prefix: String {
        var prefix = String(describing: type(of: self)).replacingOccurrences(of: "TessellationProcessor", with: "")
        prefix = prefix.replacingOccurrences(of: "Tessellation", with: "")
        prefix = prefix.replacingOccurrences(of: "Processor", with: "")
        prefix = prefix.replacingOccurrences(of: "<MTLTriangleFactorsHalf>", with: "")
        prefix = prefix.replacingOccurrences(of: "<MTLQuadTessellationFactorsHalf>", with: "")

        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != prefix {
            prefix = prefix.replacingOccurrences(of: bundleName, with: "")
        }
        prefix = prefix.replacingOccurrences(of: ".", with: "")
        return prefix
    }

    var geometry: TessellationGeometry

    public var factorsDestination: (buffer: MTLBuffer, offset: Int)?
    public var factorsLength: Int { MemoryLayout<T>.stride * geometry.patchCount }
    private var factorsWereEncoded = false

    /// Keeps existing update overrides in the dispatch path while reporting whether the
    /// standard processor actually dispatched. Custom encoders may override this operation.
    @discardableResult
    open func encodeFactors(_ commandBuffer: MTLCommandBuffer, into destination: (buffer: MTLBuffer, offset: Int), iterations: Int = 1) -> Bool {
        let previousDestination = factorsDestination
        factorsDestination = destination
        factorsWereEncoded = false
        defer { factorsDestination = previousDestination }
        update(commandBuffer, iterations: iterations)
        return factorsWereEncoded
    }

    public init(device: MTLDevice, pipelineURL: URL, live: Bool, geometry: TessellationGeometry) {
        self.geometry = geometry
        super.init(device: device, pipelineURL: pipelineURL, live: live)
    }

    override open func update() {
        super.update()
        set(geometry.controlPointBuffer, index: .TessellationPositions)
        set(geometry.indexBuffer, index: .TessellationIndices)
    }


    override func updateSize() {
        parameters.set("Count", geometry.patchCount)
    }

    // MARK: - Reset

    override public func update(_ commandBuffer: MTLCommandBuffer, iterations: Int = 1) {
        super.update(commandBuffer)
        factorsWereEncoded = false

        guard geometry.patchCount > 0, (_reset && resetPipeline != nil) || (iterations > 0 && updatePipeline != nil) else { return }

        if factorsDestination != nil, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = label
            inputCopies.withCommandBuffer(commandBuffer) {
                encode(computeEncoder, iterations: iterations)
            }
            computeEncoder.endEncoding()
        }
    }

    override public func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        super.update(computeEncoder)
        factorsWereEncoded = false

        if geometry.patchCount > 0, factorsDestination != nil {
            inputCopies.withCommandBuffer(nil) {
                encode(computeEncoder, iterations: iterations)
            }
        }
    }

    private func encode(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        bindUniforms(computeEncoder)
        bindBuffers(computeEncoder)
        bindTextures(computeEncoder)
        if let factorsDestination {
            computeEncoder.setBuffer(factorsDestination.buffer, offset: factorsDestination.offset, index: ComputeBufferIndex.TessellationFactors.rawValue)
        }

        if _reset, let pipeline = resetPipeline {
            computeEncoder.setComputePipelineState(pipeline)
            preCompute?(computeEncoder, 0)
            dispatch(
                computeEncoder: computeEncoder,
                pipeline: pipeline,
                iteration: 0
            )
            factorsWereEncoded = true
            _reset = false
        }

        if let pipeline = updatePipeline {
            computeEncoder.setComputePipelineState(pipeline)
            for iteration in 0 ..< iterations {
                preCompute?(computeEncoder, iteration)
                dispatch(
                    computeEncoder: computeEncoder,
                    pipeline: pipeline,
                    iteration: iteration
                )
                factorsWereEncoded = true
            }
        }
    }

    // MARK: - Dispatching

    #if os(macOS) || os(iOS) || os(visionOS)
        override open func dispatchThreads(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
            let patchCount = geometry.patchCount
            let threadsPerGrid = MTLSizeMake(patchCount, 1, 1)

            var threadGroupSize = pipeline.maxTotalThreadsPerThreadgroup
            threadGroupSize = threadGroupSize > patchCount ? 32 * max(patchCount / 32, 1) : threadGroupSize

            let threadsPerThreadgroup = MTLSizeMake(threadGroupSize, 1, 1)
            computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        }
    #endif

    override open func dispatchThreadgroups(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
        let maxTotalThreadsPerThreadgroup = pipeline.maxTotalThreadsPerThreadgroup
        let patchCount = geometry.patchCount
        let threadsPerThreadgroup = MTLSizeMake(maxTotalThreadsPerThreadgroup, 1, 1)
        let threadgroupsPerGrid = MTLSize(
            width: (patchCount + maxTotalThreadsPerThreadgroup - 1) / maxTotalThreadsPerThreadgroup,
            height: 1,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
}
