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
    var factorsBuffer: MTLBuffer? { get }
    func update(_ commandBuffer: MTLCommandBuffer, iterations: Int)
    func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int)
}

open class TessellationProcessor<T>: ComputeProcessor, Tessellator {
    override internal var prefix: String {
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

    var geometry: TessellationGeometry {
        didSet {
            if oldValue != geometry {
                setupFactorsBuffer()
            }
        }
    }

    public internal(set) var factorsBuffer: MTLBuffer?

    public init(device: MTLDevice, pipelineURL: URL, live: Bool, geometry: TessellationGeometry) {
        self.geometry = geometry
        super.init(device: device, pipelineURL: pipelineURL, live: live)
    }

    override public func setup() {
        setupFactorsBuffer()
        super.setup()
    }

    open override func update() {
        super.update()
        set(geometry.controlPointBuffer, index: .TessellationPositions)
        set(geometry.indexBuffer, index: .TessellationIndices)
    }

    func setupFactorsBuffer() {
        factorsBuffer = device.makeBuffer(
            length: MemoryLayout<T>.stride * geometry.patchCount,
            options: [.storageModePrivate]
        )

        factorsBuffer?.label = "\(label) Factors Buffer"
        set(factorsBuffer, index: ComputeBufferIndex.TessellationFactors)
    }

    override func updateSize() {
        parameters.set("Count", geometry.patchCount)
    }

    // MARK: - Reset

    override public func update(_ commandBuffer: MTLCommandBuffer, iterations: Int = 1) {
        super.update(commandBuffer)

        guard (_reset && resetPipeline != nil) || updatePipeline != nil else { return }

        if factorsBuffer != nil, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = label
            encode(computeEncoder, iterations: iterations)
            computeEncoder.endEncoding()
        }
    }

    override public func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        super.update(computeEncoder)

        if factorsBuffer != nil {
            encode(computeEncoder, iterations: iterations)
        }
    }

    private func encode(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        bindUniforms(computeEncoder)
        bindBuffers(computeEncoder)
        bindTextures(computeEncoder)

        if _reset, let pipeline = resetPipeline {
            computeEncoder.setComputePipelineState(pipeline)
            preCompute?(computeEncoder, 0)
            dispatch(
                computeEncoder: computeEncoder,
                pipeline: pipeline,
                iteration: 0
            )
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
