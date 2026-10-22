//
//  TextureComputeSystem.swift
//  Satin
//
//  Created by Reza Ali on 7/22/20.
//

import Metal

open class TextureComputeSystem: ComputeSystem {
    override var prefix: String {
        var prefix = String(describing: type(of: self)).replacingOccurrences(of: "TextureComputeSystem", with: "")
        prefix = prefix.replacingOccurrences(of: "ComputeSystem", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != prefix {
            prefix = prefix.replacingOccurrences(of: bundleName, with: "")
        }
        prefix = prefix.replacingOccurrences(of: ".", with: "")
        return prefix
    }

    public var textureDescriptors: [MTLTextureDescriptor] {
        didSet {
            resetTextures()
        }
    }

    public var srcTexture: MTLTexture? {
        textures[srcIndex]
    }

    public var dstTexture: MTLTexture? {
        textures[dstIndex]
    }

    public var srcTextures: [MTLTexture] {
        var results: [MTLTexture] = []
        var textureIndex = 0
        for _ in textureDescriptors {
            results.append(textures[textureIndex + srcIndex])
            textureIndex += feedbackCount
        }
        return results
    }

    public var dstTextures: [MTLTexture] {
        var results: [MTLTexture] = []
        var textureIndex = 0
        for _ in textureDescriptors {
            results.append(textures[textureIndex + dstIndex])
            textureIndex += feedbackCount
        }
        return results
    }

    open var threadsPerGrid: MTLSize?
    open var threadsPerThreadgroup: MTLSize?
    open var threadGroupsPerGrid: MTLSize?

    public var textures: [MTLTexture] = []
    private var _setupTextures = true
    private var _setupDescriptors = true

    public init(device: MTLDevice, pipelineURL: URL, textureDescriptors: [MTLTextureDescriptor], feedback: Bool = false, live: Bool = false) {
        self.textureDescriptors = textureDescriptors
        super.init(device: device, pipelineURL: pipelineURL, feedback: feedback, live: live)
    }

    public init(device: MTLDevice, pipelinesURL: URL, textureDescriptors: [MTLTextureDescriptor], feedback: Bool = false, live: Bool = false) {
        self.textureDescriptors = textureDescriptors
        super.init(device: device, pipelinesURL: pipelinesURL, feedback: feedback, live: live)
    }

    override open func setup() {
        super.setup()
        updateDescriptor()
        updateTextures()
    }

    override open func update() {
        updateDescriptor()
        updateTextures()
        super.update()
    }

    // MARK: - Descriptors

    open func setupDescriptor() {
        for textureDescriptor in textureDescriptors {
            if !textureDescriptor.usage.contains(.shaderWrite) {
                textureDescriptor.usage = [textureDescriptor.usage, .shaderWrite]
            }
            if feedback, !textureDescriptor.usage.contains(.shaderRead) {
                textureDescriptor.usage = [textureDescriptor.usage, .shaderRead]
            }
        }
    }

    private func updateDescriptor() {
        if _setupDescriptors {
            setupDescriptor()
            _setupDescriptors = false
        }
    }

    // MARK: - Textures

    open func setupTextures() {
        textures = []
        for textureDescriptor in textureDescriptors {
            for i in 0 ..< feedbackCount {
                if let texture = device.makeTexture(descriptor: textureDescriptor) {
                    texture.label = label + " Texture \(i)"
                    textures.append(texture)
                }
            }
        }
    }

    private func updateTextures() {
        if _setupTextures {
            setupTextures()
            _index = 0
            _setupTextures = false
        }
    }

    // MARK: - Size

    override func updateSize() {
        guard let txDsx = textureDescriptors.first else { return }

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

        if textures.count > 0, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = label
            encode(computeEncoder, iterations: iterations)
            computeEncoder.endEncoding()
        }
    }

    override open func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        super.update(computeEncoder)

        if textures.count > 0 {
            encode(computeEncoder, iterations: iterations)
        }
    }

    // MARK: - Binding & Encoding

    open func bind(computeEncoder: MTLComputeCommandEncoder, iteration: Int) -> Int {
        bindTextures(computeEncoder, ComputeTextureIndex.Custom0.rawValue)
    }

    private func encode(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        bindUniforms(computeEncoder)
        bindBuffers(computeEncoder)
        bindTextures(computeEncoder)

        if _reset, let pipeline = resetPipeline {
            computeEncoder.setComputePipelineState(pipeline)

            for _ in 0 ..< feedbackCount {
                var offset = bind(computeEncoder: computeEncoder, iteration: 0)
                preCompute?(computeEncoder, &offset, 0)
                dispatch(computeEncoder: computeEncoder, pipeline: pipeline, iteration: 0)
                swapSrdDstIndex()
            }

            _reset = false
        }

        if let pipeline = updatePipeline {
            computeEncoder.setComputePipelineState(pipeline)
            for iteration in 0 ..< iterations {
                var offset = bind(computeEncoder: computeEncoder, iteration: iteration)
                preCompute?(computeEncoder, &offset, iteration)
                dispatch(computeEncoder: computeEncoder, pipeline: pipeline, iteration: iteration)
                swapSrdDstIndex()
            }
        }
    }

    private func bindTextures(_ computeEncoder: MTLComputeCommandEncoder, _ offset: Int) -> Int {
        var index = offset
        var textureIndex = 0

        if feedback {
            for _ in textureDescriptors {
                computeEncoder.setTexture(textures[textureIndex + srcIndex], index: index)
                index += 1
                computeEncoder.setTexture(textures[textureIndex + dstIndex], index: index)
                index += 1
                textureIndex += 2
            }
        }
        else {
            for _ in textureDescriptors {
                computeEncoder.setTexture(textures[textureIndex], index: index)
                textureIndex += 1
                index += 1
            }
        }

        return index
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
        guard let texture = textures.first else { return }

        let threadPerGrid = threadsPerGrid ?? getThreadsPerGrid(texture: texture, iteration: iteration)
        let threadsPerThreadgroup = threadsPerThreadgroup ?? getThreadsPerThreadgroup(texture: texture, pipeline: pipeline, iteration: iteration)

        computeEncoder.dispatchThreads(threadPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    #endif

    override open func dispatchThreadgroups(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
        guard let texture = textures.first else { return }

        let threadGroupsPerGrid = threadGroupsPerGrid ?? getThreadGroupsPerGrid(texture: texture, pipeline: pipeline, iteration: iteration)
        let threadsPerThreadGroup = threadsPerThreadgroup ?? getThreadsPerThreadgroup(texture: texture, pipeline: pipeline, iteration: iteration)

        computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    }

    // MARK: - Reset

    open func resetTextures() {
        reset()
        _setupDescriptors = true
        _setupTextures = true
    }

    // MARK: - Deinit

    deinit {
        textures = []
    }
}
