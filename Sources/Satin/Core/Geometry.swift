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

/// Describes whether geometry data is expected to change after initial upload.
public enum GeometryMutability {
    case staticData
    case dynamicData
}

open class Geometry: BufferAttributeDelegate, InterleavedBufferDelegate, ElementBufferDelegate {
    public var id: String = UUID().uuidString

    public let context: Context

    // MARK: - Versioned Uploads

    public var mutability: GeometryMutability = .staticData {
        didSet {
            if mutability != oldValue {
                versionedVertexBuffers.removeAll()
                vertexBufferOffsets.removeAll()
                _updateVertexBuffers = true
            }
        }
    }

    private struct VersionedVertexBuffer {
        let buffer: MTLBuffer
        let alignedStride: Int
        let slotCount: Int
    }

    private var minimumSlotCount: Int = 1
    private var versionedSlotIndex: Int = -1
    private var latestVersionedSlotIndex: Int = -1
    private var versionedVertexBuffers: [VertexBufferIndex: VersionedVertexBuffer] = [:]
    private var vertexBufferOffsets: [VertexBufferIndex: Int] = [:]

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

    public private(set) var vertexAttributes: [VertexAttributeIndex: VertexAttribute] = [:] {
        didSet {
            _updateVertexBuffers = true
            _vertexDescriptor.clear()
        }
    }
    private var bufferAttributes: [VertexAttributeIndex: BufferAttribute] = [:]
    private var interleavedAttributes: [VertexAttributeIndex: InterleavedBufferAttribute] = [:]

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

    public init(context: Context, primitiveType: MTLPrimitiveType = .triangle, windingOrder: MTLWinding = .counterClockwise) {
        self.context = context
        self.windingOrder = windingOrder
        self.primitiveType = primitiveType
        setup()
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
            renderEncoderState.setVertexBuffer(buffer, offset: vertexBufferOffsets[index, default: 0], index: index)
        }
    }

    open func setMinimumSlotCount(_ count: Int) {
        let sanitizedCount = max(1, count)
        guard sanitizedCount != minimumSlotCount else { return }
        minimumSlotCount = sanitizedCount
        versionedVertexBuffers.removeAll()
        vertexBufferOffsets.removeAll()
        versionedSlotIndex = -1
        latestVersionedSlotIndex = -1
        _updateVertexBuffers = true
    }

    public func selectRecentSlot(iteration: Int, count: Int) {
        guard usesVersionedVertexBuffers, latestVersionedSlotIndex >= 0 else { return }
        let sanitizedCount = max(1, count)
        let clampedIteration = min(max(0, iteration), sanitizedCount - 1)
        let distanceFromCurrent = sanitizedCount - 1 - clampedIteration
        versionedSlotIndex = (latestVersionedSlotIndex - distanceFromCurrent + requiredVersionedSlotCount) % requiredVersionedSlotCount

        for (bufferIndex, versionedBuffer) in versionedVertexBuffers {
            vertexBuffers[bufferIndex] = versionedBuffer.buffer
            vertexBufferOffsets[bufferIndex] = versionedBuffer.alignedStride * versionedSlotIndex
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

    public func getAttribute(_ index: VertexAttributeIndex) -> VertexAttribute? {
        vertexAttributes[index]
    }

    public func addAttribute(_ attribute: VertexAttribute, for index: VertexAttributeIndex) {
        vertexAttributes[index] = attribute
        if let bufferAttribute = attribute as? BufferAttribute {
            bufferAttributes[index] = bufferAttribute
            interleavedAttributes.removeValue(forKey: index)
            bufferAttribute.delegate = self
        } else if let interleavedBuffer = attribute as? InterleavedBufferAttribute {
            interleavedAttributes[index] = interleavedBuffer
            bufferAttributes.removeValue(forKey: index)
            interleavedBuffer.parent.delegate = self
        } else {
            bufferAttributes.removeValue(forKey: index)
            interleavedAttributes.removeValue(forKey: index)
        }
    }

    public func removeAttribute(_ index: VertexAttributeIndex) {
        if let attribute = vertexAttributes[index] {
            if let bufferAttribute = attribute as? BufferAttribute {
                bufferAttribute.delegate = nil
            } else if let interleavedAttribute = attribute as? InterleavedBufferAttribute {
                interleavedAttribute.parent.delegate = nil
            }
            vertexAttributes.removeValue(forKey: index)
            bufferAttributes.removeValue(forKey: index)
            interleavedAttributes.removeValue(forKey: index)
        }
    }

    public func removeAttributes() {
        for (index, attribute) in vertexAttributes {
            if let bufferAttribute = attribute as? BufferAttribute {
                bufferAttribute.delegate = nil
            } else if let interleavedAttribute = attribute as? InterleavedBufferAttribute {
                interleavedAttribute.parent.delegate = nil
            }
            vertexAttributes.removeValue(forKey: index)
        }
        bufferAttributes.removeAll()
        interleavedAttributes.removeAll()
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
        let device = context.device
        if usesVersionedVertexBuffers {
            advanceVersionedSlot()
        }
        for (attributeIndex, attribute) in bufferAttributes {
            setupBufferAttribute(device, attribute: attribute, for: attributeIndex)
        }
        for attribute in interleavedAttributes.values {
            setupInterleavedBufferAttribute(device, attribute: attribute)
        }
    }

    // MARK: - Setup Index Buffer

    private func setupIndexBuffer() {
        guard let elementBuffer else { return }
        indexBuffer = elementBuffer.getBuffer(device: context.device)
    }

    // MARK: - Setup Vertex Attributes

    private func setupBufferAttribute(_ device: MTLDevice, attribute: BufferAttribute, for index: VertexAttributeIndex) {
        let bufferIndex = index.bufferIndex

        guard attribute.needsUpdate || vertexBuffers[bufferIndex] == nil else { return }

        if usesVersionedVertexBuffers {
            let data = attribute.getData()
            data.withUnsafeBytes { dataPointer in
                uploadVersionedVertexBuffer(
                    dataPointer.baseAddress,
                    length: data.count,
                    bufferIndex: bufferIndex,
                    label: index.name
                )
            }
        }
        else if let buffer = attribute.getBuffer(device: device) {
            buffer.label = index.name
            vertexBuffers[bufferIndex] = buffer
            vertexBufferOffsets[bufferIndex] = 0
        }
        else {
            vertexBuffers.removeValue(forKey: bufferIndex)
            vertexBufferOffsets.removeValue(forKey: bufferIndex)
        }

        attribute.needsUpdate = false
    }

    private func setupInterleavedBufferAttribute(_ device: MTLDevice, attribute: InterleavedBufferAttribute) {
        let interleavedBuffer = attribute.parent
        let bufferIndex = interleavedBuffer.index

        guard interleavedBuffer.needsUpdate || vertexBuffers[bufferIndex] == nil else { return }

        if usesVersionedVertexBuffers {
            uploadVersionedVertexBuffer(
                interleavedBuffer.data,
                length: interleavedBuffer.length,
                bufferIndex: bufferIndex,
                label: bufferIndex.label
            )
            interleavedBuffer.needsUpdate = false
        }
        else if let buffer = interleavedBuffer.getBuffer(device: device) {
            buffer.label = bufferIndex.label
            vertexBuffers[bufferIndex] = buffer
            vertexBufferOffsets[bufferIndex] = 0
        }
        else {
            vertexBuffers[bufferIndex] = nil
            vertexBufferOffsets.removeValue(forKey: bufferIndex)
        }
    }

    // MARK: - Vertex Descriptor

    open func generateVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()

        for (attributeIndex, attribute) in bufferAttributes {
            let index = attributeIndex.rawValue
            let bufferIndex = attributeIndex.bufferIndex.rawValue
            descriptor.attributes[index].format = attribute.format
            descriptor.attributes[index].offset = 0
            descriptor.attributes[index].bufferIndex = bufferIndex

            descriptor.layouts[bufferIndex].stride = attribute.stride
            descriptor.layouts[bufferIndex].stepRate = attribute.stepRate
            descriptor.layouts[bufferIndex].stepFunction = attribute.stepFunction
        }

        for (attributeIndex, interleavedAttribute) in interleavedAttributes {
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
        else if let interleavedBufferAttribute = positionAttribute as? InterleavedBufferAttribute {
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
            else if let interleavedBufferAttribute = positionAttribute as? InterleavedBufferAttribute {
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

    // MARK: - Versioned Vertex Buffers

    private var usesVersionedVertexBuffers: Bool {
        mutability == .dynamicData && minimumSlotCount > 1
    }

    private var requiredVersionedSlotCount: Int {
        max(1, minimumSlotCount * context.maxBuffersInFlight)
    }

    private func advanceVersionedSlot() {
        versionedSlotIndex = (versionedSlotIndex + 1) % requiredVersionedSlotCount
        latestVersionedSlotIndex = versionedSlotIndex
    }

    private func uploadVersionedVertexBuffer(_ source: UnsafeRawPointer?,
                                             length: Int,
                                             bufferIndex: VertexBufferIndex,
                                             label: String)
    {
        guard length > 0, let source else {
            vertexBuffers.removeValue(forKey: bufferIndex)
            vertexBufferOffsets.removeValue(forKey: bufferIndex)
            versionedVertexBuffers.removeValue(forKey: bufferIndex)
            return
        }

        if versionedSlotIndex < 0 {
            advanceVersionedSlot()
        }

        let alignedStride = align256(size: length)
        let slotCount = requiredVersionedSlotCount
        let existing = versionedVertexBuffers[bufferIndex]

        let versionedBuffer: VersionedVertexBuffer
        if let existing,
           existing.alignedStride >= alignedStride,
           existing.slotCount >= slotCount
        {
            versionedBuffer = existing
        }
        else {
            guard let buffer = context.device.makeBuffer(
                length: alignedStride * slotCount,
                options: [.cpuCacheModeWriteCombined]
            ) else { return }
            buffer.label = "\(label) Versioned"
            versionedBuffer = VersionedVertexBuffer(
                buffer: buffer,
                alignedStride: alignedStride,
                slotCount: slotCount
            )
            versionedVertexBuffers[bufferIndex] = versionedBuffer
        }

        let offset = versionedBuffer.alignedStride * versionedSlotIndex
        memcpy(versionedBuffer.buffer.contents().advanced(by: offset), source, length)

        vertexBuffers[bufferIndex] = versionedBuffer.buffer
        vertexBufferOffsets[bufferIndex] = offset
    }

    // MARK: - Deinit

    deinit {
        removeAttributes()

        vertexAttributes.removeAll()
        vertexBuffers.removeAll()
        vertexBufferOffsets.removeAll()
        versionedVertexBuffers.removeAll()

        elementBuffer?.delegate = nil
        elementBuffer = nil
        indexBuffer = nil
    }

    // MARK: - Updated Buffer Attribute Data

    public func updated(attribute: BufferAttribute) {
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
