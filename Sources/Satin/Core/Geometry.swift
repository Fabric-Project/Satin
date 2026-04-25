//
//  Geometry.swift
//
//
//  Created by Reza Ali on 7/13/23.
//

import Combine
import Foundation
import Metal

#if SWIFT_PACKAGE
import SatinCore
#endif

// add on change publishers for vertex & index data

open class Geometry: BufferAttributeDelegate, InterleavedBufferDelegate, ElementBufferDelegate {
    public var id: String = UUID().uuidString

    public var context: Context? {
        didSet {
            if oldValue == nil, context != oldValue {
                setup()
            }
        }
    }

    public var windingOrder: MTLWinding = .counterClockwise
    public var primitiveType: MTLPrimitiveType = .triangle {
        didSet {
            if primitiveType != oldValue, primitiveType != .triangle {
                updateBVH = true
            }
        }
    }

    private var _vertexDescriptor = ValueCache<MTLVertexDescriptor>()
    public var vertexDescriptor: MTLVertexDescriptor { _vertexDescriptor.get { generateVertexDescriptor() } }
    public var tessellationDescriptor: TessellationDescriptor? { nil }

    public private(set) var vertexAttributes: [VertexAttributeIndex: any VertexAttribute] = [:] {
        didSet {
            _updateVertexBuffers = true
            _vertexDescriptor.clear()
        }
    }

    public let onUpdate = PassthroughSubject<Geometry, Never>()

    public var vertexCount: Int { vertexAttributes[.Position]?.count ?? 0 }
    public private(set) var vertexBuffers: [VertexBufferIndex: MTLBuffer] = [:]

    private var _updateVertexBuffers = true {
        didSet {
            if _updateVertexBuffers {
                updateBounds = true
                updateBVH = true
                onUpdate.send(self)
            }
        }
    }

    public internal(set) var elementBuffer: ElementBuffer? {
        didSet {
            if oldValue != elementBuffer, elementBuffer != nil {
                _updateIndexBuffer = true
            }
        }
    }

    public var indexType: MTLIndexType? { elementBuffer?.type }
    public var indexCount: Int { elementBuffer?.count ?? 0 }

    public private(set) var indexBuffer: MTLBuffer? {
        didSet {
            _updateIndexBuffer = false
        }
    }

    private var _updateIndexBuffer = true {
        didSet {
            if _updateIndexBuffer {
                updateBounds = true
                updateBVH = true
                onUpdate.send(self)
            }
        }
    }

    public var updateBVH = true

    private var _bvh: BVH?
    public var bvh: BVH? {
        if updateBVH, primitiveType == .triangle {
            _bvh = createBVH()
            updateBVH = false
        }
        return _bvh
    }

    public var updateBounds = true

    private var _bounds: Bounds = createBounds()
    public var bounds: Bounds {
        if updateBounds {
            _bounds = computeBounds()
            updateBounds = false
        }
        return _bounds
    }

    // MARK: - Init

    public init(primitiveType: MTLPrimitiveType = .triangle, windingOrder: MTLWinding = .counterClockwise) {
        self.windingOrder = windingOrder
        self.primitiveType = primitiveType
    }

    open func setup() {
        updateBuffers()
    }

    open func update() {
        updateBuffers()
    }

    open func encode(_ commandBuffer: MTLCommandBuffer) {}

    // MARK: - Bind

    open func bind(renderEncoderState: RenderEncoderState, shadow: Bool) {
        for (index, buffer) in vertexBuffers {
            renderEncoderState.setVertexBuffer(buffer, offset: 0, index: index)
        }
    }

    // MARK: - Draw

    open func draw(renderEncoderState: RenderEncoderState, instanceCount: Int, indexBufferOffset: Int = 0, vertexStart: Int = 0) {
        let renderEncoder = renderEncoderState.renderEncoder
        if let indexBuffer = indexBuffer, let indexType = indexType {
            if indexCount > 0 {
                renderEncoder.drawIndexedPrimitives(
                    type: primitiveType,
                    indexCount: indexCount,
                    indexType: indexType,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: indexBufferOffset,
                    instanceCount: instanceCount
                )
            }
        }
        else {
            if vertexCount > 0 {
                renderEncoder.drawPrimitives(
                    type: primitiveType,
                    vertexStart: vertexStart,
                    vertexCount: vertexCount,
                    instanceCount: instanceCount
                )
            }
        }
    }

    // MARK: - Elements

    public func setElements(_ elementBuffer: ElementBuffer?) {
        if let oldElementBuffer = self.elementBuffer {
            oldElementBuffer.delegate = nil
        }

        self.elementBuffer = elementBuffer
        if let newElementBuffer = self.elementBuffer {
            newElementBuffer.delegate = self
        }
    }

    // MARK: - Attributes

    public func getAttribute(_ index: VertexAttributeIndex) -> (any VertexAttribute)? {
        vertexAttributes[index]
    }

    public func addAttribute(_ attribute: any VertexAttribute, for index: VertexAttributeIndex) {
        vertexAttributes[index] = attribute
        if let bufferAttribute = attribute as? any BufferAttribute {
            bufferAttribute.delegate = self
        }
        else if let interleavedBuffer = attribute as? any InterleavedBufferAttribute {
            interleavedBuffer.parent.delegate = self
        }
    }

    public func removeAttribute(_ index: VertexAttributeIndex) {
        if let attribute = vertexAttributes[index] {
            if let bufferAttribute = attribute as? any BufferAttribute {
                bufferAttribute.delegate = nil
            }
            vertexAttributes.removeValue(forKey: index)
        }
    }

    public func removeAttributes() {
        for (index, attribute) in vertexAttributes {
            if let bufferAttribute = attribute as? any BufferAttribute {
                bufferAttribute.delegate = nil
            }
            else if let interleavedAttribute = attribute as? (any InterleavedBufferAttribute) {
                interleavedAttribute.parent.delegate = nil
            }
            vertexAttributes.removeValue(forKey: index)
        }
    }

    public func hasAttribute(_ index: VertexAttributeIndex) -> Bool {
        return vertexAttributes[index] != nil
    }

    // MARK: - Update Buffers

    private func updateBuffers() {
        if _updateVertexBuffers {
            setupVertexBuffers()
            _updateVertexBuffers = false
        }
        if _updateIndexBuffer {
            setupIndexBuffer()
            _updateIndexBuffer = false
        }
    }

    // MARK: - Setup Vertex Buffers

    private func setupVertexBuffers() {
        guard let device = context?.device else { return }
        for (attributeIndex, attribute) in vertexAttributes {
            if let bufferAttribute = attribute as? any BufferAttribute {
                setupBufferAttribute(device, attribute: bufferAttribute, for: attributeIndex)
            }
            else if let interleavedBufferAttribute = attribute as? any InterleavedBufferAttribute {
                setupInterleavedBufferAttribute(device, attribute: interleavedBufferAttribute)
            }
        }
    }

    // MARK: - Setup Index Buffer

    private func setupIndexBuffer() {
        guard let device = context?.device, let elementBuffer else { return }
        indexBuffer = elementBuffer.getBuffer(device: device)
    }

    // MARK: - Setup Vertex Attributes

    private func setupBufferAttribute(_ device: MTLDevice, attribute: any BufferAttribute, for index: VertexAttributeIndex) {
        let bufferIndex = index.bufferIndex

        guard attribute.needsUpdate || vertexBuffers[bufferIndex] == nil else { return }

        if let buffer = attribute.getBuffer(device: device) {
            buffer.label = index.name
            vertexBuffers[bufferIndex] = buffer
        }
        else {
            vertexBuffers.removeValue(forKey: bufferIndex)
        }

        attribute.needsUpdate = false
    }

    private func setupInterleavedBufferAttribute(_ device: MTLDevice, attribute: any InterleavedBufferAttribute) {
        let interleavedBuffer = attribute.parent
        let bufferIndex = interleavedBuffer.index

        guard interleavedBuffer.needsUpdate || vertexBuffers[bufferIndex] == nil else { return }

        if let buffer = interleavedBuffer.getBuffer(device: device) {
            buffer.label = bufferIndex.label
            vertexBuffers[bufferIndex] = buffer
        }
        else {
            vertexBuffers[bufferIndex] = nil
        }
    }

    // MARK: - Vertex Descriptor

    open func generateVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()

        for (attributeIndex, attribute) in vertexAttributes {
            if let interleavedAttribute = attribute as? any InterleavedBufferAttribute {
                let index = attributeIndex.rawValue
                let interleavedBuffer = interleavedAttribute.parent
                let bufferIndex = interleavedBuffer.index.rawValue

                descriptor.attributes[index].format = interleavedAttribute.format
                descriptor.attributes[index].offset = interleavedAttribute.offset
                descriptor.attributes[index].bufferIndex = bufferIndex

                descriptor.layouts[bufferIndex].stride = interleavedBuffer.stride
                descriptor.layouts[bufferIndex].stepRate = interleavedBuffer.stepRate
                descriptor.layouts[bufferIndex].stepFunction = interleavedBuffer.stepFunction
            }
            else {
                let index = attributeIndex.rawValue
                let bufferIndex = attributeIndex.bufferIndex.rawValue
                descriptor.attributes[index].format = attribute.format
                descriptor.attributes[index].offset = 0
                descriptor.attributes[index].bufferIndex = bufferIndex

                descriptor.layouts[bufferIndex].stride = attribute.stride
                descriptor.layouts[bufferIndex].stepRate = attribute.stepRate
                descriptor.layouts[bufferIndex].stepFunction = attribute.stepFunction
            }
        }

        return descriptor
    }

    // MARK: - BVH

    private func createBVH() -> BVH {
        guard let positionAttribute = vertexAttributes[.Position] else { return BVH() }

        if let positionBufferAttribute = positionAttribute as? Float4BufferAttribute {
            return createBVHFromFloatData(
                &positionBufferAttribute.data,
                Int32(positionBufferAttribute.stride/MemoryLayout<Float>.size),
                Int32(positionBufferAttribute.count),
                elementBuffer?.data,
                Int32(indexCount),
                elementBuffer?.type == .uint32,
                false
            )
        }
        else if let positionBufferAttribute = positionAttribute as? Float3BufferAttribute {
            return createBVHFromFloatData(
                &positionBufferAttribute.data,
                Int32(positionBufferAttribute.stride/MemoryLayout<Float>.size),
                Int32(positionBufferAttribute.count),
                elementBuffer?.data,
                Int32(indexCount),
                elementBuffer?.type == .uint32,
                false
            )
        }
        else if let interleavedBufferAttribute = positionAttribute as? (any InterleavedBufferAttribute) {
            let interleavedBuffer = interleavedBufferAttribute.parent
            return createBVHFromFloatData(
                interleavedBuffer.data,
                Int32(interleavedBuffer.stride/MemoryLayout<Float>.size),
                Int32(interleavedBuffer.count),
                elementBuffer?.data,
                Int32(indexCount),
                elementBuffer?.type == .uint32,
                false
            )
        }
        else {
            return BVH()
        }
    }

    // MARK: - Bounds

    open func computeBounds() -> Bounds {
        if primitiveType == .triangle, let bvh = bvh, let node = bvh.getNode(index: 0) {
            return node.aabb
        }
        else if let positionAttribute = vertexAttributes[.Position] {
            if let positionBufferAttribute = positionAttribute as? Float4BufferAttribute {
                return computeBoundsFromFloatData(
                    &positionBufferAttribute.data,
                    Int32(positionBufferAttribute.stride/MemoryLayout<Float>.size),
                    Int32(positionBufferAttribute.count)
                )
            }
            else if let positionBufferAttribute = positionAttribute as? Float3BufferAttribute {
                return computeBoundsFromFloatData(
                    &positionBufferAttribute.data,
                    Int32(positionBufferAttribute.stride/MemoryLayout<Float>.size),
                    Int32(positionBufferAttribute.count)
                )
            }
            else if let interleavedBufferAttribute = positionAttribute as? (any InterleavedBufferAttribute) {
                let interleavedBuffer = interleavedBufferAttribute.parent
                return computeBoundsFromFloatData(
                    interleavedBuffer.data,
                    Int32(interleavedBuffer.stride/MemoryLayout<Float>.size),
                    Int32(interleavedBuffer.count)
                )
            }
        }

        return createBounds()
    }

    // MARK: - Intersects

    public func intersects(ray: Ray) -> Bool {
        return rayBoundsIntersect(ray, bounds)
    }

    public func intersect(ray: Ray, intersections: inout [IntersectionResult]) {
        bvh?.intersect(ray: ray, intersections: &intersections)
    }

    // MARK: - Deinit

    deinit {
        removeAttributes()

        vertexAttributes.removeAll()
        vertexBuffers.removeAll()

        elementBuffer?.delegate = nil
        elementBuffer = nil
        indexBuffer = nil
    }

    // MARK: - Updated Buffer Attribute Data

    public func updated(attribute: any BufferAttribute) {
        _updateVertexBuffers = true
    }

    // MARK: - Updated Interleaved Buffer Data {

    public func updated(buffer: InterleavedBuffer) {
        _updateVertexBuffers = true
    }

    // MARK: - Updated Element Buffer Data {

    public func updated(buffer: ElementBuffer) {
        _updateIndexBuffer = true
    }
}

extension Geometry: Equatable {
    public static func == (lhs: Geometry, rhs: Geometry) -> Bool {
        return lhs === rhs
    }
}

extension Geometry: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
