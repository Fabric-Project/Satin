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

/// How a geometry divides into rigid pieces: the pieces of a cut, glyphs of text, islands of a mesh.
/// A piece may contain pieces (a word holds glyphs; a piece of a first cut holds the pieces of a
/// second), stored flat as in glTF and USD skeletons: piece `i` is index `i` in every array, and
/// each piece names its parent.
///
/// Contract with the geometry that carries it:
/// - Every vertex belongs to exactly one lowest-level piece and carries that piece's index as its
///   joint (JointIndices x, JointWeights 1). A pose is then one matrix per piece, a model-space
///   delta from rest; a parent's matrix composes into its children's.
/// - Vertices are laid out depth-first, so each piece's range covers its whole subtree: a parent
///   spans its children, and a lowest-level piece spans its own vertices.
/// - Everything is in the geometry's local space and units.
///
/// Built once by whatever makes the pieces and cached on the geometry; new pieces are a new value.
/// The initializer checks every invariant, so a value that exists is well formed.
public struct GeometryPieces: Equatable {
    /// What `sizes` measures: closed pieces have volume; open ones, such as flat text, area.
    public enum SizeMeasure: Equatable {
        case volume
        case area
    }

    /// One piece, read across the arrays.
    public struct Piece: Equatable {
        public let center: simd_float3
        public let size: Float
        public let parentIndex: Int
        public let vertexRange: Range<Int>
    }

    public enum ValidationError: Error, Equatable {
        /// The arrays do not all have one entry per piece.
        case mismatchedCounts
        /// A parent index is out of range or not before its child.
        case parentNotBeforeChild(piece: Int)
        /// A piece's vertices are not inside its parent's.
        case rangeOutsideParent(piece: Int)
        /// Siblings' vertices overlap or are out of order.
        case siblingsOverlap(piece: Int)
        /// A size is negative or not finite.
        case invalidSize(piece: Int)
        /// A parent's size is not the sum of its children's.
        case parentSizeMismatch(piece: Int)
    }

    /// Each piece's parent in these same arrays, or -1 for a top-level piece. Parents come
    /// before their children.
    public let parentIndices: [Int]
    /// Each piece's pivot at rest.
    public let centers: [simd_float3]
    /// Each piece's volume or area (see `sizeMeasure`); a parent's is the sum of its children's.
    public let sizes: [Float]
    public let sizeMeasure: SizeMeasure
    /// Each piece's vertices, covering its whole subtree.
    public let vertexRanges: [Range<Int>]

    public var count: Int { parentIndices.count }

    public subscript(index: Int) -> Piece {
        Piece(center: centers[index], size: sizes[index], parentIndex: parentIndices[index], vertexRange: vertexRanges[index])
    }

    public init(parentIndices: [Int], centers: [simd_float3], sizes: [Float], sizeMeasure: SizeMeasure, vertexRanges: [Range<Int>]) throws {
        let count = parentIndices.count
        guard centers.count == count, sizes.count == count, vertexRanges.count == count else { throw ValidationError.mismatchedCounts }

        var childSizeSums = [Float](repeating: 0, count: count)
        var hasChildren = [Bool](repeating: false, count: count)
        // The end of the last sibling seen under each parent (top level keyed by -1).
        var lastSiblingEnd: [Int: Int] = [:]
        for piece in 0..<count {
            let size = sizes[piece]
            guard size.isFinite, size >= 0 else { throw ValidationError.invalidSize(piece: piece) }
            let parent = parentIndices[piece]
            guard parent == -1 || (parent >= 0 && parent < piece) else { throw ValidationError.parentNotBeforeChild(piece: piece) }
            let range = vertexRanges[piece]
            if parent >= 0 {
                let parentRange = vertexRanges[parent]
                guard range.lowerBound >= parentRange.lowerBound, range.upperBound <= parentRange.upperBound else {
                    throw ValidationError.rangeOutsideParent(piece: piece)
                }
                childSizeSums[parent] += size
                hasChildren[parent] = true
            }
            if let previousEnd = lastSiblingEnd[parent], range.lowerBound < previousEnd { throw ValidationError.siblingsOverlap(piece: piece) }
            lastSiblingEnd[parent] = range.upperBound
        }
        for piece in 0..<count where hasChildren[piece] {
            let tolerance = max(abs(sizes[piece]), abs(childSizeSums[piece])) * 1e-4 + 1e-12
            guard abs(sizes[piece] - childSizeSums[piece]) <= tolerance else { throw ValidationError.parentSizeMismatch(piece: piece) }
        }

        self.parentIndices = parentIndices
        self.centers = centers
        self.sizes = sizes
        self.sizeMeasure = sizeMeasure
        self.vertexRanges = vertexRanges
    }
}

open class Geometry: BufferAttributeDelegate, InterleavedBufferDelegate, ElementBufferDelegate {
    public var id: String = UUID().uuidString

    public let context: Context

    // MARK: - Versioned Uploads

    public var mutability: GeometryMutability = .staticData {
        didSet {
            if mutability != oldValue {
                versionedVertexBuffers.removeAll()
                versionedIndexBuffer = nil
                vertexBufferOffsets.removeAll()
                drawStates.removeAll()
                selectedDrawState = nil
                _updateVertexBuffers = true
            }
        }
    }

    private struct VersionedVertexBuffer {
        let buffer: MTLBuffer
        let alignedStride: Int
        let slotCount: Int
    }

    private struct VersionedIndexBuffer {
        let buffer: MTLBuffer
        let alignedStride: Int
        let slotCount: Int
    }

    private struct DrawState {
        let vertexBuffers: [VertexBufferIndex: MTLBuffer]
        let vertexBufferOffsets: [VertexBufferIndex: Int]
        let indexBuffer: MTLBuffer?
        let indexBufferOffset: Int
        let indexType: MTLIndexType?
        let indexCount: Int
        let vertexCount: Int
        let primitiveType: MTLPrimitiveType
    }

    public private(set) var minimumEncodesPerFrame: Int = 1
    private var versionedSlotIndex: Int = -1
    private var latestVersionedSlotIndex: Int = -1
    private var versionedVertexBuffers: [VertexBufferIndex: VersionedVertexBuffer] = [:]
    private var vertexBufferOffsets: [VertexBufferIndex: Int] = [:]
    private var versionedIndexBuffer: VersionedIndexBuffer?
    private var indexBufferOffset = 0
    private var drawStates: [Int: DrawState] = [:]
    private var selectedDrawState: DrawState?

    public var windingOrder: MTLWinding = .counterClockwise
    public var primitiveType: MTLPrimitiveType = .triangle {
        didSet {
            if primitiveType != oldValue, primitiveType != .triangle {
                updateBVH = true
            }
        }
    }

    private var _vertexDescriptor = ValueCache<MTLVertexDescriptor>()
    open var vertexDescriptor: MTLVertexDescriptor { _vertexDescriptor.get { generateVertexDescriptor() } }
    public var tessellationDescriptor: TessellationDescriptor? { nil }

    public private(set) var vertexAttributes: [VertexAttributeIndex: VertexAttribute] = [:] {
        didSet {
            // Clear first: setting the flag tells meshes, which read the new layout at once.
            _vertexDescriptor.clear()
            _updateVertexBuffers = true
        }
    }
    private var bufferAttributes: [VertexAttributeIndex: BufferAttribute] = [:]
    private var interleavedAttributes: [VertexAttributeIndex: InterleavedBufferAttribute] = [:]

    public let onUpdate = PassthroughSubject<Geometry, Never>()

    public var vertexCount: Int { vertexAttributes[.Position]?.count ?? 0 }

    /// The pose of this geometry's joints. Together with `JointIndices` and `JointWeights`
    /// attributes it makes the geometry skinned: any mesh drawing it, with any standard
    /// material, moves its vertices by the palette on the GPU.
    public var jointPalette: JointPalette? {
        didSet {
            // A palette attached after repeated encoding was prepared needs the same room.
            if minimumEncodesPerFrame > 1 { jointPalette?.prepareForRepeatedEncoding(count: minimumEncodesPerFrame) }
            // Meshes listen for this to switch their materials' skinning on or off.
            if (jointPalette == nil) != (oldValue == nil) { onUpdate.send(self) }
        }
    }

    /// How this geometry divides into rigid pieces; nil for ordinary geometry. Whoever sets it
    /// also gives the vertices their piece indices as joints (see `GeometryPieces`).
    open var pieces: GeometryPieces?

    /// Has a joint palette and the joint attributes it applies to.
    open var isSkinned: Bool {
        jointPalette != nil && vertexAttributes[.JointIndices] != nil && vertexAttributes[.JointWeights] != nil
    }
    public private(set) var vertexBuffers: [VertexBufferIndex: MTLBuffer] = [:]

    /// Has vertex data on the GPU, so a mesh can draw it.
    open var hasVertexBuffers: Bool { !vertexBuffers.isEmpty }

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
            if oldValue != elementBuffer {
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
        // A skinned geometry's bounds follow its pose.
        if isSkinned, let jointPalette, jointPalette !== boundsPalette || jointPalette.poseVersion != boundsPoseVersion {
            updateBounds = true
        }
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
        if isSkinned, let jointPalette {
            renderEncoderState.vertexJointPalette = jointPalette
        }
    }

    // TODO(render-packets): repeated-encoding stopgap; see Renderable.prepareForRepeatedEncoding.
    open func setMinimumEncodesPerFrame(_ encodesPerFrame: Int) {
        let sanitizedCount = max(1, encodesPerFrame)
        if sanitizedCount > 1 { jointPalette?.prepareForRepeatedEncoding(count: sanitizedCount) }
        guard sanitizedCount != minimumEncodesPerFrame else { return }
        minimumEncodesPerFrame = sanitizedCount
        versionedVertexBuffers.removeAll()
        versionedIndexBuffer = nil
        drawStates.removeAll()
        versionedSlotIndex = -1
        latestVersionedSlotIndex = -1
        selectedDrawState = nil
    }

    /// After an iteration's update in repeated encoding: records what that iteration draws,
    /// such as its joint palette pose.
    open func captureRepeatedEncoding(iteration: Int, count: Int) {
        jointPalette?.captureRepeatedEncoding(iteration: iteration, count: count)
    }

    open func selectRecentSlot(iteration: Int, count: Int) {
        jointPalette?.selectRecentSlot(iteration: iteration, count: count)
        guard usesVersionedDrawStates, latestVersionedSlotIndex >= 0 else { return }
        let sanitizedCount = max(1, count)
        let clampedIteration = min(max(0, iteration), sanitizedCount - 1)
        let distanceFromCurrent = sanitizedCount - 1 - clampedIteration
        versionedSlotIndex = (latestVersionedSlotIndex - distanceFromCurrent + requiredVersionedSlotCount) % requiredVersionedSlotCount
        guard let drawState = drawStates[versionedSlotIndex] else { return }

        selectedDrawState = drawState
        vertexBuffers = drawState.vertexBuffers
        vertexBufferOffsets = drawState.vertexBufferOffsets
        indexBuffer = drawState.indexBuffer
        indexBufferOffset = drawState.indexBufferOffset
    }

    // MARK: - Draw

    open func draw(renderEncoderState: RenderEncoderState, instanceCount: Int, indexBufferOffset: Int = 0, vertexStart: Int = 0) {
        let renderEncoder = renderEncoderState.renderEncoder
        let drawState = selectedDrawState
        let drawPrimitiveType = drawState?.primitiveType ?? primitiveType
        let drawIndexBuffer = drawState?.indexBuffer ?? indexBuffer
        let drawIndexType = drawState?.indexType ?? indexType
        let drawIndexCount = drawState?.indexCount ?? indexCount
        let drawIndexBufferOffset = (drawState?.indexBufferOffset ?? self.indexBufferOffset) + indexBufferOffset
        let drawVertexCount = drawState?.vertexCount ?? vertexCount

        if let indexBuffer = drawIndexBuffer, let indexType = drawIndexType {
            if drawIndexCount > 0 {
                renderEncoder.drawIndexedPrimitives(
                    type: drawPrimitiveType,
                    indexCount: drawIndexCount,
                    indexType: indexType,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: drawIndexBufferOffset,
                    instanceCount: instanceCount
                )
            }
        }
        else {
            if drawVertexCount > 0 {
                renderEncoder.drawPrimitives(
                    type: drawPrimitiveType,
                    vertexStart: vertexStart,
                    vertexCount: drawVertexCount,
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
        if !usesVersionedDrawStates {
            selectedDrawState = nil
        }

        if usesVersionedDrawStates {
            advanceVersionedSlot()
        }

        if _updateVertexBuffers {
            setupVertexBuffers()
            _updateVertexBuffers = false
        }
        if _updateIndexBuffer {
            setupIndexBuffer()
            _updateIndexBuffer = false
        }

        if usesVersionedDrawStates {
            captureVersionedDrawState()
        }
    }

    // MARK: - Setup Vertex Buffers

    private func setupVertexBuffers() {
        let device = context.device
        for (attributeIndex, attribute) in bufferAttributes {
            setupBufferAttribute(device, attribute: attribute, for: attributeIndex)
        }
        for attribute in interleavedAttributes.values {
            setupInterleavedBufferAttribute(device, attribute: attribute)
        }
    }

    // MARK: - Setup Index Buffer

    private func setupIndexBuffer() {
        guard let elementBuffer else {
            indexBuffer = nil
            indexBufferOffset = 0
            return
        }

        if usesVersionedDrawStates {
            uploadVersionedIndexBuffer(elementBuffer)
        }
        else {
            indexBuffer = elementBuffer.getBuffer(device: context.device)
            indexBufferOffset = 0
        }
    }

    // MARK: - Setup Vertex Attributes

    private func setupBufferAttribute(_ device: MTLDevice, attribute: BufferAttribute, for index: VertexAttributeIndex) {
        let bufferIndex = index.bufferIndex

        guard attribute.needsUpdate || vertexBuffers[bufferIndex] == nil else { return }

        if usesVersionedDrawStates {
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

        if usesVersionedDrawStates {
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
        if let posedBVH = currentPosedBVH(), let node = posedBVH.getNode(index: 0) {
            boundsPalette = jointPalette
            boundsPoseVersion = jointPalette?.poseVersion ?? -1
            return node.aabb
        }
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

    /// Skinned geometry is hit where its pose draws it.
    open func intersect(ray: Ray, intersections: inout [IntersectionResult]) {
        if let posedBVH = currentPosedBVH() {
            posedBVH.intersect(ray: ray, intersections: &intersections)
        } else {
            bvh?.intersect(ray: ray, intersections: &intersections)
        }
    }

    // MARK: - Posed Bounds and Raycasts

    /// The geometry whose vertex attributes a pose moves: this one, or a view's source.
    open var skinningSource: Geometry { self }

    private var posedBVH: BVH?
    private weak var posedBVHPalette: JointPalette?
    private var posedBVHPoseVersion = -1
    private weak var boundsPalette: JointPalette?
    private var boundsPoseVersion = -1

    /// The triangles where the joint palette draws them, skinned on the CPU exactly as the
    /// vertex shader does and rebuilt only when bounds or a raycast need them after the pose
    /// changed. Nil unless skinned triangles with CPU-readable positions, joint indices
    /// (UShort4) and weights (Float4).
    func currentPosedBVH() -> BVH? {
        guard isSkinned, primitiveType == .triangle, let jointPalette else { return nil }
        if let posedBVH, posedBVHPalette === jointPalette, posedBVHPoseVersion == jointPalette.poseVersion {
            return posedBVH
        }
        let source = skinningSource
        guard let positions = Self.skinnedPositions(of: source, palette: jointPalette) else { return nil }
        let vertexCount = positions.count / 3
        let bvh = positions.withUnsafeBytes { bytes in
            createBVHFromFloatData(bytes.baseAddress, 3, Int32(vertexCount), source.elementBuffer?.data,
                                   Int32(source.indexCount), source.elementBuffer?.type == .uint32, false)
        }
        if let posedBVH { freeBVH(posedBVH) }
        posedBVH = bvh
        posedBVHPalette = jointPalette
        posedBVHPoseVersion = jointPalette.poseVersion
        return bvh
    }

    /// Each vertex's posed position, packed xyz: the weighted sum of its joints' current
    /// matrices applied to its rest position, as `satinSkinMatrix` computes it.
    private static func skinnedPositions(of geometry: Geometry, palette: JointPalette) -> [Float]? {
        guard let jointIndices = geometry.getAttribute(.JointIndices) as? UShort4BufferAttribute,
              let jointWeights = geometry.getAttribute(.JointWeights) as? Float4BufferAttribute,
              let restPositions = restPositions(of: geometry)
        else { return nil }
        let joints = palette.joints
        var posed = [Float]()
        posed.reserveCapacity(restPositions.count * 3)
        for vertexIndex in restPositions.indices {
            let rest = simd_float4(restPositions[vertexIndex], 1)
            var position = simd_float4.zero
            if vertexIndex < jointIndices.data.count, vertexIndex < jointWeights.data.count {
                let indices = jointIndices.data[vertexIndex]
                let weights = jointWeights.data[vertexIndex]
                for influence in 0..<4 where weights[influence] != 0 && Int(indices[influence]) < joints.count {
                    position += weights[influence] * (joints[Int(indices[influence])].current * rest)
                }
            }
            posed += [position.x, position.y, position.z]
        }
        return posed
    }

    /// Rest positions from a Float3 or Float4 buffer attribute or an interleaved one.
    private static func restPositions(of geometry: Geometry) -> [simd_float3]? {
        switch geometry.getAttribute(.Position) {
        case let attribute as Float3BufferAttribute:
            return attribute.data
        case let attribute as Float4BufferAttribute:
            return attribute.data.map { simd_make_float3($0) }
        case let attribute as InterleavedBufferAttribute:
            let buffer = attribute.parent
            guard let data = buffer.data else { return nil }
            return (0..<buffer.count).map { vertexIndex in
                let vertex = data.advanced(by: vertexIndex * buffer.stride + attribute.offset)
                return simd_float3(vertex.loadUnaligned(as: Float.self),
                                   vertex.loadUnaligned(fromByteOffset: 4, as: Float.self),
                                   vertex.loadUnaligned(fromByteOffset: 8, as: Float.self))
            }
        default:
            return nil
        }
    }

    // MARK: - Versioned Draw State

    private var usesVersionedDrawStates: Bool {
        minimumEncodesPerFrame > 1
    }

    private var requiredVersionedSlotCount: Int {
        max(1, minimumEncodesPerFrame * context.maxBuffersInFlight)
    }

    private func advanceVersionedSlot() {
        versionedSlotIndex = (versionedSlotIndex + 1) % requiredVersionedSlotCount
        latestVersionedSlotIndex = versionedSlotIndex
    }

    private func captureVersionedDrawState() {
        guard versionedSlotIndex >= 0 else { return }
        drawStates[versionedSlotIndex] = DrawState(
            vertexBuffers: vertexBuffers,
            vertexBufferOffsets: vertexBufferOffsets,
            indexBuffer: indexBuffer,
            indexBufferOffset: indexBufferOffset,
            indexType: indexType,
            indexCount: indexCount,
            vertexCount: vertexCount,
            primitiveType: primitiveType
        )
        selectedDrawState = drawStates[versionedSlotIndex]
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

    private func uploadVersionedIndexBuffer(_ elementBuffer: ElementBuffer) {
        guard elementBuffer.count > 0, elementBuffer.length > 0, let source = elementBuffer.data else {
            indexBuffer = nil
            indexBufferOffset = 0
            versionedIndexBuffer = nil
            elementBuffer.markClean()
            return
        }

        if versionedSlotIndex < 0 {
            advanceVersionedSlot()
        }

        let alignedStride = align256(size: elementBuffer.length)
        let slotCount = requiredVersionedSlotCount
        let existing = versionedIndexBuffer

        let versionedBuffer: VersionedIndexBuffer
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
            buffer.label = "Indices Versioned"
            versionedBuffer = VersionedIndexBuffer(
                buffer: buffer,
                alignedStride: alignedStride,
                slotCount: slotCount
            )
            versionedIndexBuffer = versionedBuffer
        }

        let offset = versionedBuffer.alignedStride * versionedSlotIndex
        memcpy(versionedBuffer.buffer.contents().advanced(by: offset), source, elementBuffer.length)

        indexBuffer = versionedBuffer.buffer
        indexBufferOffset = offset
        elementBuffer.markClean()
    }

    // MARK: - Deinit

    deinit {
        if let posedBVH { freeBVH(posedBVH) }
        removeAttributes()

        vertexAttributes.removeAll()
        vertexBuffers.removeAll()
        vertexBufferOffsets.removeAll()
        versionedVertexBuffers.removeAll()
        versionedIndexBuffer = nil
        drawStates.removeAll()
        selectedDrawState = nil

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
