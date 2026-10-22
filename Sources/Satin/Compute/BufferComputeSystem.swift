//
//  BufferComputeSystem.swift
//  Satin
//
//  Created by Reza Ali on 4/13/20.
//

import Combine
import Metal
import simd

public protocol BufferComputeSystemDelegate: AnyObject {
    func updated(bufferComputeSystem: BufferComputeSystem)
}

open class BufferComputeSystem: ComputeSystem {
    override var prefix: String {
        var prefix = String(describing: type(of: self)).replacingOccurrences(of: "BufferComputeSystem", with: "")
        prefix = prefix.replacingOccurrences(of: "ComputeSystem", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != prefix {
            prefix = prefix.replacingOccurrences(of: bundleName, with: "")
        }
        prefix = prefix.replacingOccurrences(of: ".", with: "")
        return prefix
    }

    public var count: Int {
        didSet {
            if count != oldValue {
                resetBuffers()
            }
        }
    }

    public private(set) var buffers: [ParameterGroup] = [] {
        didSet {
            resetBuffers()
        }
    }

    private var bufferResourceOptions: MTLResourceOptions
    private var bufferOrder: [String] = []
    private var bufferMap: [String: [MTLBuffer]] = [:]
    private var bufferParametersSubscription: AnyCancellable?

    private var _setupBuffers = true

    override public internal(set) var shader: ComputeShader? {
        didSet {
            if shader != oldValue, let shader = shader {
                setupShaderBufferParametersSubscription(shader)
            }
        }
    }

    // MARK: - Init

    public init(device: MTLDevice, pipelineURL: URL, count: Int, feedback: Bool = false, live: Bool = false, bufferResourceOptions: MTLResourceOptions = .storageModePrivate) {
        assert(count > 0, "Buffer Compute System count: \(count) must be greater than zero!")
        self.count = count
        self.bufferResourceOptions = bufferResourceOptions
        super.init(device: device, pipelineURL: pipelineURL, feedback: feedback, live: live)
    }

    public init(device: MTLDevice, pipelinesURL: URL, count: Int, feedback: Bool = false, live: Bool = false, bufferResourceOptions: MTLResourceOptions = .storageModePrivate) {
        assert(count > 0, "Buffer Compute System count: \(count) must be greater than zero!")
        self.count = count
        self.bufferResourceOptions = bufferResourceOptions
        super.init(device: device, pipelinesURL: pipelinesURL, feedback: feedback, live: live)
    }

    // MARK: - Setup

    override open func setup() {
        super.setup()
        setupBuffers()
    }

    // MARK: - Update

    override open func update() {
        updateBuffers()
        super.update()
    }

    override open func update(_ commandBuffer: MTLCommandBuffer, iterations: Int = 1) {
        super.update(commandBuffer)

        guard (_reset && resetPipeline != nil) || updatePipeline != nil else { return }

        if count > 0, bufferMap.count > 0, let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = label
            encode(computeEncoder, iterations: iterations)
            computeEncoder.endEncoding()
        }
    }

    override open func update(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        super.update(computeEncoder)
        if count > 0, bufferMap.count > 0 {
            encode(computeEncoder, iterations: iterations)
        }
    }

    open func bind(_ computeEncoder: MTLComputeCommandEncoder) -> Int {
        bindBuffers(computeEncoder, ComputeBufferIndex.Custom0.rawValue)
    }

    private func encode(_ computeEncoder: MTLComputeCommandEncoder, iterations: Int = 1) {
        bindUniforms(computeEncoder)
        bindBuffers(computeEncoder)
        bindTextures(computeEncoder)

        if _reset, let pipeline = resetPipeline {
            computeEncoder.setComputePipelineState(pipeline)

            for _ in 0 ..< feedbackCount {
                var offset = bind(computeEncoder)
                preCompute?(computeEncoder, &offset, 0)
                dispatch(computeEncoder: computeEncoder, pipeline: pipeline, iteration: 0)
                swapSrdDstIndex()
            }

            _reset = false
        } else if let pipeline = updatePipeline {
            computeEncoder.setComputePipelineState(pipeline)
            for iteration in 0 ..< iterations {
                var offset = bind(computeEncoder)
                preCompute?(computeEncoder, &offset, iteration)
                dispatch(computeEncoder: computeEncoder, pipeline: pipeline, iteration: iteration)
                swapSrdDstIndex()
            }
        }
    }

    func setupShaderBufferParametersSubscription(_ shader: ComputeShader) {
        bufferParametersSubscription = shader.buffersPublisher.sink { [weak self] buffers in
            self?.updateBuffers(buffers)
        }
    }

    // MARK: - Size

    override func updateSize() {
        parameters.set("Count", count)
    }

    // MARK: - Buffers

    public func getBuffer(_ label: String) -> MTLBuffer? {
        if let buffers = bufferMap[label] ?? bufferMap[label.titleCase] {
            return buffers[dstIndex]
        }
        return nil
    }

    public func getSourceBuffer(_ label: String) -> MTLBuffer? {
        if let buffers = bufferMap[label] ?? bufferMap[label.titleCase] {
            return buffers[srcIndex]
        }
        return nil
    }

    public func getDestinationBuffer(_ label: String) -> MTLBuffer? {
        getBuffer(label)
    }

    private func setupBuffers() {
        guard count > 0 else { return }
        bufferMap = [:]
        bufferOrder = []

        for param in buffers where param.stride > 0 {
            let stride = param.stride
            let label = param.label

            bufferMap[label] = []
            bufferOrder.append(label)

            var buffers: [MTLBuffer] = []
            for i in 0 ..< feedbackCount {
                if let buffer = device.makeBuffer(length: stride * count, options: bufferResourceOptions) {
                    buffer.label = label + " \(i)"
                    buffers.append(buffer)
                }
            }

            bufferMap[label] = buffers
        }

        _index = 0
        _count = count
        _setupBuffers = false
    }

    private func updateBuffers() {
        if _setupBuffers {
            setupBuffers()
        }
    }

    private func updateBuffers(_ buffers: [ParameterGroup]) {
        self.buffers = buffers
//        objectWillChange.send()
        delegate?.updated(computeSystem: self)
    }

    private func bindBuffers(_ computeEncoder: MTLComputeCommandEncoder, _ offset: Int) -> Int {
        var indexOffset = offset
        if feedback {
            for key in bufferOrder {
                if let buffers = bufferMap[key] {
                    let inBuffer = buffers[srcIndex]
                    let outBuffer = buffers[dstIndex]
                    computeEncoder.setBuffer(inBuffer, offset: 0, index: indexOffset)
                    indexOffset += 1
                    computeEncoder.setBuffer(outBuffer, offset: 0, index: indexOffset)
                    indexOffset += 1
                }
            }
        } else {
            for key in bufferOrder {
                if let buffers = bufferMap[key] {
                    computeEncoder.setBuffer(buffers[srcIndex], offset: 0, index: indexOffset)
                    indexOffset += 1
                }
            }
        }
        return indexOffset
    }

    // MARK: - Reset

    open func resetBuffers() {
        reset()
        _setupBuffers = true
    }

    // MARK: - Dispatching

    #if os(macOS) || os(iOS) || os(visionOS)
    override open func dispatchThreads(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
        let gridSize = MTLSizeMake(_count, 1, 1)

        var threadGroupSize = pipeline.maxTotalThreadsPerThreadgroup
        threadGroupSize = threadGroupSize > _count ? 32 * max(_count / 32, 1) : threadGroupSize

        let threadsPerThreadgroup = MTLSizeMake(threadGroupSize, 1, 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    #endif

    override open func dispatchThreadgroups(computeEncoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, iteration: Int) {
        let m = pipeline.maxTotalThreadsPerThreadgroup
        let threadsPerThreadgroup = MTLSizeMake(m, 1, 1)
        let threadgroupsPerGrid = MTLSize(width: (_count + m - 1) / m, height: 1, depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    // MARK: - Deinit

    deinit {
        buffers = []
        bufferMap = [:]
        bufferOrder = []
    }
}
