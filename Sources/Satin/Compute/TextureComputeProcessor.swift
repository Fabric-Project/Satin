//
//  TextureComputeProcessor.swift
//  Satin
//
//  Created by Reza Ali on 9/7/24.
//

import Foundation
import Metal

open class TextureComputeProcessor: ComputeProcessor {
    override var prefix: String {
        var prefix = String(describing: type(of: self)).replacingOccurrences(of: "TextureComputeProcessor", with: "")
        prefix = prefix.replacingOccurrences(of: "Texture", with: "")
        prefix = prefix.replacingOccurrences(of: "Compute", with: "")
        prefix = prefix.replacingOccurrences(of: "Processor", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != prefix {
            prefix = prefix.replacingOccurrences(of: bundleName, with: "")
        }
        prefix = prefix.replacingOccurrences(of: ".", with: "")
        return prefix
    }

    open var threadsPerGrid: MTLSize?
    open var threadsPerThreadgroup: MTLSize?
    open var threadGroupsPerGrid: MTLSize?

    // MARK: - Textures

    // MARK: - Size

    override func updateSize() {
        guard let txDsx = computeTextures[.Custom0] else { return }

        if txDsx.textureType == .type1D || txDsx.textureType == .type1DArray {
            parameters.set("Size", txDsx.width)
        }
        else if txDsx.textureType == .type2D || txDsx.textureType == .type2DArray {
            parameters.set("Size", [txDsx.width, txDsx.height])
        }
        else if txDsx.textureType == .type3D {
            parameters.set("Size", [txDsx.width, txDsx.height, txDsx.depth])
        }
        else if txDsx.textureType == .typeCube || txDsx.textureType == .typeCubeArray {
            parameters.set("Size", [txDsx.width, txDsx.height])
        }
    }

    // MARK: - Reset

    override open func update(_ commandBuffer: MTLCommandBuffer, iterations: Int = 1) {
        super.update(commandBuffer)

        guard (_reset && resetPipeline != nil) || updatePipeline != nil else { return }

        if computeTextures.count > 0, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = label
            encode(computeEncoder, iterations: iterations)
            computeEncoder.endEncoding()
        }
    }

    override open func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        super.update(computeEncoder)

        if computeTextures.count > 0 {
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

    open func getSize(texture: MTLTexture, iteration: Int) -> MTLSize {
        MTLSize(width: texture.width, height: texture.height, depth: texture.depth)
    }

    open func getThreadsPerGrid(texture: MTLTexture, iteration: Int) -> MTLSize {
        getSize(texture: texture, iteration: iteration)
    }

    open func getThreadGroupsPerGrid(texture: MTLTexture, pipeline: MTLComputePipelineState, iteration: Int) -> MTLSize {
        let threadExecutionWidth = pipeline.threadExecutionWidth
        let maxTotalThreadsPerThreadgroup = pipeline.maxTotalThreadsPerThreadgroup

        let size = getSize(texture: texture, iteration: iteration)

        if texture.depth > 1 {
            var w = Int(pow(Float(maxTotalThreadsPerThreadgroup), 1.0 / 3.0))
            if w > threadExecutionWidth {
                w = threadExecutionWidth
            }

            let threadgroupsPerGrid = MTLSize(width: (size.width + w - 1) / w,
                                              height: (size.height + w - 1) / w,
                                              depth: (size.depth + w - 1) / w)

            return threadgroupsPerGrid
        }
        else {
            let w = threadExecutionWidth
            let h = maxTotalThreadsPerThreadgroup / w

            let threadgroupsPerGrid = MTLSize(width: (size.width + w - 1) / w,
                                              height: (size.height + h - 1) / h,
                                              depth: 1)

            return threadgroupsPerGrid
        }
    }

    open func getThreadsPerThreadgroup(texture: MTLTexture, pipeline: MTLComputePipelineState, iteration: Int) -> MTLSize {
        let threadExecutionWidth = pipeline.threadExecutionWidth
        let maxTotalThreadsPerThreadgroup = pipeline.maxTotalThreadsPerThreadgroup

        if texture.depth > 1 {
            let startWidth = threadExecutionWidth / 2 // 16
            let startHeight = startWidth // 16
            let startDepth = (maxTotalThreadsPerThreadgroup / startWidth) / startHeight

            var threadsPerThreadgroup = MTLSizeMake(startWidth, startHeight, startDepth)
            while (threadsPerThreadgroup.width * threadsPerThreadgroup.height * threadsPerThreadgroup.depth) > maxTotalThreadsPerThreadgroup {
                if (threadsPerThreadgroup.width / 2 * threadsPerThreadgroup.height / 2 * threadsPerThreadgroup.depth) < maxTotalThreadsPerThreadgroup {
                    threadsPerThreadgroup.width /= 2
                    threadsPerThreadgroup.height /= 2
                }
                else {
                    threadsPerThreadgroup.depth /= 2
                }
            }
            var w = Int(pow(Float(maxTotalThreadsPerThreadgroup), 1.0 / 3.0))
            if w > threadExecutionWidth {
                w = threadExecutionWidth
            }

            return threadsPerThreadgroup
        }
        else if texture.height > 1 {
            return MTLSizeMake(threadExecutionWidth, maxTotalThreadsPerThreadgroup / threadExecutionWidth, 1)
        }
        else {
            return MTLSizeMake(threadExecutionWidth, 1, 1)
        }
    }

    #if os(macOS) || os(iOS) || os(visionOS)
        override open func dispatchThreads(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
            guard let texture = computeTextures[.Custom0] else { return }

            let threadPerGrid = threadsPerGrid ?? getThreadsPerGrid(texture: texture, iteration: iteration)
            let threadsPerThreadgroup = threadsPerThreadgroup ?? getThreadsPerThreadgroup(texture: texture, pipeline: pipeline, iteration: iteration)

            computeEncoder.dispatchThreads(threadPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        }
    #endif

    override open func dispatchThreadgroups(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
        guard let texture = computeTextures[.Custom0] else { return }

        let threadGroupsPerGrid = threadGroupsPerGrid ?? getThreadGroupsPerGrid(texture: texture, pipeline: pipeline, iteration: iteration)
        let threadsPerThreadGroup = threadsPerThreadgroup ?? getThreadsPerThreadgroup(texture: texture, pipeline: pipeline, iteration: iteration)

        computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    }

    // MARK: - Reset

    open func resetTextures() {
        reset()
    }

    // MARK: - Deinit

    deinit {}
}
