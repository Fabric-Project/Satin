//
//  Object.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Combine
import Foundation
import Metal
import simd
import Synchronization

#if SWIFT_PACKAGE
import SatinCore
#endif

open class Object: Codable {
    var id: String = UUID().uuidString

    public var label = "Object"

    public var visible = true

    public let context: Context

    // MARK: - Position

    public var position: simd_float3 = .zero {
        didSet {
            guard position != oldValue else { return }
            localTransformCache.translationMatrix = nil
            localTransformDidChange()
        }
    }

    public var worldPosition: simd_float3 {
        get {
            validateWorld()
            if let cached = worldTransformCache.position { return cached }
            let position = simd_make_float3(worldMatrix.columns.3)
            worldTransformCache.position = position
            return position
        }
        set {
            if let parent = parent {
                position = simd_make_float3(parent.worldMatrixInverse * simd_make_float4(newValue, 1.0))
            } else {
                position = newValue
            }
        }
    }

    public var translationMatrix: matrix_float4x4 {
        if let cached = localTransformCache.translationMatrix { return cached }
        let matrix = translationMatrix3f(position)
        localTransformCache.translationMatrix = matrix
        return matrix
    }

    // MARK: - Orientation

    public var orientation = simd_quatf(matrix_identity_float4x4) {
        didSet {
            guard orientation != oldValue else { return }
            localTransformCache.clearRotation()
            localTransformDidChange()
        }
    }

    public var worldOrientation: simd_quatf {
        get {
            // Keeps a mirrored world matrix's rotation a rotation; see `worldScale`.
            validateWorld()
            if let cached = worldTransformCache.orientation { return cached }
            let orientation = worldMatrix.decomposed.rotation
            worldTransformCache.orientation = orientation
            return orientation
        }
        set {
            if let parent = parent {
                orientation = parent.worldOrientation.inverse * newValue
            } else {
                orientation = newValue
            }
        }
    }

    public var rotationMatrix: matrix_float4x4 {
        if let cached = localTransformCache.rotationMatrix { return cached }
        let matrix = matrix_float4x4(orientation)
        localTransformCache.rotationMatrix = matrix
        return matrix
    }

    // MARK: - Scale

    public var scale: simd_float3 = .one {
        didSet {
            guard scale != oldValue else { return }
            localTransformCache.scaleMatrix = nil
            localTransformDidChange()
        }
    }

    public var worldScale: simd_float3 {
        get {
            // A mirrored world matrix keeps its handedness as a negative x scale.
            validateWorld()
            if let cached = worldTransformCache.scale { return cached }
            let scale = worldMatrix.decomposed.scale
            worldTransformCache.scale = scale
            return scale
        }
        set {
            if let parent = parent {
                scale = newValue / parent.worldScale
            } else {
                scale = newValue
            }
        }
    }

    public var scaleMatrix: matrix_float4x4 {
        if let cached = localTransformCache.scaleMatrix { return cached }
        let matrix = scaleMatrix3f(scale)
        localTransformCache.scaleMatrix = matrix
        return matrix
    }

    // MARK: - Local Matrix

    public var localMatrix: matrix_float4x4 {
        get {
            if let cached = localTransformCache.matrix { return cached }
            let matrix = simd_mul(simd_mul(translationMatrix, rotationMatrix), scaleMatrix)
            localTransformCache.matrix = matrix
            return matrix
        }
        set {
            // Keeps a mirrored matrix mirrored, as a negative x scale. One change, not three.
            let decomposition = newValue.decomposed
            guard decomposition.translation != position || decomposition.scale != scale || decomposition.rotation != orientation else { return }
            isAssigningLocalMatrix = true
            position = decomposition.translation
            scale = decomposition.scale
            orientation = decomposition.rotation
            isAssigningLocalMatrix = false
            localTransformDidChange()
        }
    }

    public var localMatrixInverse: matrix_float4x4 {
        if let cached = localTransformCache.matrixInverse { return cached }
        let inverse = localMatrix.inverse
        localTransformCache.matrixInverse = inverse
        return inverse
    }

    /// Values derived from this object's own transform. One stored struct, so a setter clears what
    /// it invalidates in one exclusivity check. A getter checks, computes outside the access and
    /// stores, because a computation reads other local values.
    private struct LocalTransformCache {
        var translationMatrix: matrix_float4x4?
        var rotationMatrix: matrix_float4x4?
        var scaleMatrix: matrix_float4x4?
        var matrix: matrix_float4x4?
        var matrixInverse: matrix_float4x4?
        var forwardDirection: simd_float3?
        var upDirection: simd_float3?
        var rightDirection: simd_float3?

        mutating func clearRotation() {
            rotationMatrix = nil
            forwardDirection = nil
            upDirection = nil
            rightDirection = nil
        }

        mutating func clearMatrix() {
            matrix = nil
            matrixInverse = nil
        }
    }

    private var localTransformCache = LocalTransformCache()

    // MARK: - Revisions

    /// Advances when this object's own transform (position, orientation, scale) changes value.
    public private(set) var localRevision: UInt64 = 0

    /// Advances whenever any object's transform or parent changes, in any scene on any thread. Only
    /// a shortcut: an object validated at the current epoch knows nothing above it moved. Not a
    /// revision of any object. Atomic, so scenes owned by different threads share it safely; a
    /// change elsewhere only costs another object one ancestor walk. Relaxed is enough: each scene
    /// still has one owner, which orders its own changes before its own reads.
    static let transformEpoch = Atomic<UInt64>(0)

    #if DEBUG
    /// This object's validations that had to look at its parent: the epoch had moved.
    private(set) var worldValidationWalkCount = 0
    #endif

    private var isAssigningLocalMatrix = false

    private func localTransformDidChange() {
        guard !isAssigningLocalMatrix else { return }
        localTransformCache.clearMatrix()
        localRevision &+= 1
        Object.transformEpoch.wrappingAdd(1, ordering: .relaxed)
        // Descendant changes still mark ancestor bounds: a parent's cached bounds can't find out
        // about a child by looking.
        updateLocalBounds = true
    }

    /// What the world transform was last derived from: the parent (identity and link), the
    /// parent's world revision, and this object's local revision. One stored struct, read once
    /// and written once per validation, so it costs one or two exclusivity checks, not a dozen.
    private struct WorldValidation {
        var revision: UInt64 = 0
        var parentIdentity: ObjectIdentifier?
        var parentLinkRevision: UInt64 = 0
        var parentRevision: UInt64 = 0
        var localRevision: UInt64 = 0
        var isDerived = false
        var validatedEpoch: UInt64 = .max
    }

    private var worldValidation = WorldValidation()

    /// Advances whenever this object's world transform may have changed: its own transform, an
    /// ancestor's, or its parent. Reading it validates against the ancestors first, so it is
    /// current without reading any matrix.
    public var worldRevision: UInt64 {
        validateWorld()
        return worldValidation.revision
    }

    /// Brings the world-derived caches up to date with the ancestors: clears them, and advances
    /// `worldRevision`, when what they were derived from changed. Returns at once while nothing
    /// anywhere has moved since the last validation.
    func validateWorld() {
        let epoch = Object.transformEpoch.load(ordering: .relaxed)
        guard worldValidation.validatedEpoch != epoch else { return }
        #if DEBUG
        worldValidationWalkCount += 1
        #endif
        let parent = self.parent
        let link = parentLink
        let parentIdentity = link.identifier
        let parentRevision = parent?.worldRevision ?? 0
        let parentLinkRevision = link.revision
        let localRevision = self.localRevision
        var validation = worldValidation
        let changed = !validation.isDerived || parentIdentity != validation.parentIdentity
            || parentLinkRevision != validation.parentLinkRevision
            || parentRevision != validation.parentRevision || localRevision != validation.localRevision
        if changed
        {
            validation.isDerived = true
            validation.parentIdentity = parentIdentity
            validation.parentLinkRevision = parentLinkRevision
            validation.parentRevision = parentRevision
            validation.localRevision = localRevision
            validation.revision &+= 1
        }
        validation.validatedEpoch = epoch
        worldValidation = validation
        if changed { clearWorldTransformCache() }
    }

    private func clearWorldTransformCache() {
        worldTransformCache = WorldTransformCache()
    }

    /// Values derived from the world transform, valid until `validateWorld()` sees it change.
    /// One stored struct, so clearing them all is one exclusivity check, not nine. A getter checks,
    /// computes outside the access and stores, because a computation reads other world values.
    private struct WorldTransformCache {
        var position: simd_float3?
        var orientation: simd_quatf?
        var scale: simd_float3?
        var matrix: matrix_float4x4?
        var matrixInverse: matrix_float4x4?
        var normalMatrix: matrix_float3x3?
        var forwardDirection: simd_float3?
        var upDirection: simd_float3?
        var rightDirection: simd_float3?
    }

    private var worldTransformCache = WorldTransformCache()

    // MARK: - World Matrix

    public var worldMatrix: matrix_float4x4 {
        get {
            validateWorld()
            if let cached = worldTransformCache.matrix { return cached }
            let matrix: matrix_float4x4
            if let parent = parent {
                matrix = simd_mul(parent.worldMatrix, localMatrix)
            } else {
                matrix = localMatrix
            }
            worldTransformCache.matrix = matrix
            return matrix
        }
        set {
            if let parent = parent {
                localMatrix = parent.worldMatrixInverse * newValue
            } else {
                localMatrix = newValue
            }
        }
    }

    public var worldMatrixInverse: matrix_float4x4 {
        validateWorld()
        if let cached = worldTransformCache.matrixInverse { return cached }
        let inverse = worldMatrix.inverse
        worldTransformCache.matrixInverse = inverse
        return inverse
    }

    // MARK: - Normal Bounds

    public var normalMatrix: matrix_float3x3 {
        validateWorld()
        if let cached = worldTransformCache.normalMatrix { return cached }
        let n = worldMatrixInverse.transpose
        let normalMatrix = simd_matrix(simd_make_float3(n.columns.0), simd_make_float3(n.columns.1), simd_make_float3(n.columns.2))
        worldTransformCache.normalMatrix = normalMatrix
        return normalMatrix
    }

    // MARK: - Bounds

    /// Marking stops at an object already marked: its ancestors were marked with it, and no
    /// ancestor's bounds depend on a descendant's. Its own local and world bounds are always marked.
    public var updateBounds = true {
        didSet {
            guard updateBounds else { return }
            updateBounds = false
            let wasMarked = _updateBounds
            _updateBounds = true
            if !wasMarked { parent?.updateBounds = true }
        }
    }

    var _updateBounds = true {
        didSet {
            updateLocalBounds = true
        }
    }

    var _bounds = createBounds()
    public var bounds: Bounds {
        if _updateBounds {
            _bounds = computeBounds()
            _updateBounds = false
        }
        return _bounds
    }

    // MARK: - Local Bounds

    /// Stops at an object already marked, like `updateBounds`. World bounds are marked on every
    /// call, since reading world bounds doesn't clear the local mark.
    public var updateLocalBounds = true {
        didSet {
            guard updateLocalBounds else { return }
            updateLocalBounds = false
            let wasMarked = _updateLocalBounds
            _updateLocalBounds = true
            if !wasMarked { parent?.updateLocalBounds = true }
        }
    }

    var _updateLocalBounds = true {
        didSet {
            if _updateLocalBounds {
                updateWorldBounds = true
            }
        }
    }

    var _localBounds = createBounds()
    public var localBounds: Bounds {
        if _updateLocalBounds {
            _localBounds = computeLocalBounds()
            _updateLocalBounds = false
        }
        return _localBounds
    }

    // MARK: - World Bounds

    /// Stops at an object already marked. Computing world bounds reads every child's world
    /// bounds, so an object is only ever cleared with its marked descendants: a marked object's
    /// ancestors are all marked. Without the early-out, every mark walked to the root.
    var updateWorldBounds = true {
        didSet {
            guard updateWorldBounds else { return }
            updateWorldBounds = false
            guard !_updateWorldBounds else { return }
            _updateWorldBounds = true
            parent?.updateWorldBounds = true
        }
    }

    var _updateWorldBounds = true
    /// The world revision the world bounds were computed at: an ancestor's move is seen by
    /// revision, a descendant's change by `updateWorldBounds`.
    private var worldBoundsRevision: UInt64 = 0

    var _worldBounds = createBounds()
    public var worldBounds: Bounds {
        let revision = worldRevision
        if _updateWorldBounds || revision != worldBoundsRevision {
            _worldBounds = computeWorldBounds()
            _updateWorldBounds = false
            worldBoundsRevision = revision
        }
        return _worldBounds
    }

    // MARK: - Directions

    public var forwardDirection: simd_float3 {
        if let cached = localTransformCache.forwardDirection { return cached }
        let direction = simd_normalize(orientation.act(Satin.worldForwardDirection))
        localTransformCache.forwardDirection = direction
        return direction
    }

    public var upDirection: simd_float3 {
        if let cached = localTransformCache.upDirection { return cached }
        let direction = simd_normalize(orientation.act(Satin.worldUpDirection))
        localTransformCache.upDirection = direction
        return direction
    }

    public var rightDirection: simd_float3 {
        if let cached = localTransformCache.rightDirection { return cached }
        let direction = simd_normalize(orientation.act(Satin.worldRightDirection))
        localTransformCache.rightDirection = direction
        return direction
    }

    // MARK: - World Directions

    public var worldForwardDirection: simd_float3 {
        validateWorld()
        if let cached = worldTransformCache.forwardDirection { return cached }
        let direction = simd_normalize(worldOrientation.act(Satin.worldForwardDirection))
        worldTransformCache.forwardDirection = direction
        return direction
    }

    public var worldUpDirection: simd_float3 {
        validateWorld()
        if let cached = worldTransformCache.upDirection { return cached }
        let direction = simd_normalize(worldOrientation.act(Satin.worldUpDirection))
        worldTransformCache.upDirection = direction
        return direction
    }

    public var worldRightDirection: simd_float3 {
        validateWorld()
        if let cached = worldTransformCache.rightDirection { return cached }
        let direction = simd_normalize(worldOrientation.act(Satin.worldRightDirection))
        worldTransformCache.rightDirection = direction
        return direction
    }

    // MARK: - Parent & Children

    /// The object whose `children` hold this one. Checked `unowned`, so a parent needs no side
    /// table: the parent clears it when it lets this object go and as it deallocates, so it never
    /// outlives its target.
    unowned var parent: Object? {
        didSet {
            parentLink = ParentLink(identifier: parent.map(ObjectIdentifier.init), revision: parentLink.revision &+ 1)
            Object.transformEpoch.wrappingAdd(1, ordering: .relaxed)
            updateWorldBounds = true
            // An already-marked object stops its own walk; the new parent still needs marking.
            parent?.updateWorldBounds = true
        }
    }

    /// The parent's identity, compared without loading the parent (as a deallocating parent must),
    /// and a revision that advances when `parent` is assigned. Written together, read together.
    private struct ParentLink {
        var identifier: ObjectIdentifier?
        var revision: UInt64 = 0
    }

    private var parentLink = ParentLink()

    /// The objects this one contains, in order. Assigning it, or changing it in place, updates scene
    /// membership the same way `add` and `remove` do.
    public var children: [Object] {
        get { _children }
        set {
            let previousChildren = _children
            _children = newValue

            let previousIdentifiers = Set(previousChildren.map(ObjectIdentifier.init))
            let newIdentifiers = Set(newValue.map(ObjectIdentifier.init))
            for child in previousChildren where !newIdentifiers.contains(ObjectIdentifier(child)) {
                child.removeContainer(ObjectIdentifier(self))
                if child.parentLink.identifier == ObjectIdentifier(self) {
                    child.parent = nil
                }
            }
            for child in newValue where !previousIdentifiers.contains(ObjectIdentifier(child)) {
                registerAsContainer(of: child)
            }

            childrenDidChange()
        }
    }

    private var _children: [Object] = []

    // MARK: - Scene Structure

    /// An object whose `children` contain this one. Checked `unowned`, so a container needs no side
    /// table: a container removes its link when it lets this object go and as it deallocates.
    private struct ContainerLink {
        unowned let object: Object
        let identifier: ObjectIdentifier
    }

    /// Every object whose `children` contain this one, once each: its parent, and any object it
    /// was attached to. Structure changes travel up through these. A handful at most: a scan.
    private var containers = ContiguousArray<ContainerLink>()

    /// Advances whenever this object's subtree changes structure.
    private(set) var structureRevision: UInt64 = 0

    private var lastStructureChangeToken: UInt64 = 0
    /// Hands out one token per structure change, unique across every scene and thread.
    private static let structureChangeTokenCount = Atomic<UInt64>(0)

    private var cachedSceneIndex: SceneIndex?

    /// This object's descendants, flattened and cast, rebuilt only after its structure changes.
    public var sceneIndex: SceneIndex {
        if let cachedSceneIndex, cachedSceneIndex.revision == structureRevision {
            return cachedSceneIndex
        }
        let sceneIndex = SceneIndex(root: self)
        cachedSceneIndex = sceneIndex
        return sceneIndex
    }

    private func registerAsContainer(of child: Object) {
        let identifier = ObjectIdentifier(self)
        for link in child.containers where link.identifier == identifier { return }
        child.containers.append(ContainerLink(object: self, identifier: identifier))
    }

    private func removeContainer(_ identifier: ObjectIdentifier) {
        for index in containers.indices where containers[index].identifier == identifier {
            containers.remove(at: index)
            return
        }
    }

    private func childrenDidChange() {
        updateLocalBounds = true
        let token = Object.structureChangeTokenCount.wrappingAdd(1, ordering: .relaxed).newValue
        structureDidChange(token: token)
    }

    /// Marks this object and every container above it as structurally changed, once per change.
    private func structureDidChange(token: UInt64) {
        guard lastStructureChangeToken != token else { return }
        lastStructureChangeToken = token
        structureRevision &+= 1
        cachedSceneIndex = nil

        for link in containers {
            link.object.structureDidChange(token: token)
        }
    }

    // MARK: - OnUpdate Hook

    public var onUpdate: (() -> Void)?

    // MARK: - Init

    public init(context: Context, label: String = "Object", visible: Bool = true, _ children: [Object] = []) {
        self.context = context
        self.label = label
        self.visible = visible
        for child in children {
            add(child)
        }
        setup()
    }

    // MARK: - Deinit

    /// Clears every link a child holds to this object, without loading it: nothing it contains
    /// keeps an `unowned` link to it.
    deinit {
        let identifier = ObjectIdentifier(self)
        for child in _children {
            child.removeContainer(identifier)
            if child.parentLink.identifier == identifier {
                child.parent = nil
            }
        }
    }

    // MARK: - CodingKeys

    public enum CodingKeys: String, CodingKey {
        case id
        case label
        case position
        case orientation
        case scale
        case visible
        case children
    }

    // MARK: - Decode

    public required init(from decoder: Decoder) throws {
        context = try decoder.requireSatinContext(typeName: String(describing: type(of: self)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = try values.decode(String.self, forKey: .label)
        position = try values.decode(simd_float3.self, forKey: .position)
        scale = try values.decode(simd_float3.self, forKey: .scale)
        orientation = try values.decode(simd_quatf.self, forKey: .orientation)
        visible = try values.decode(Bool.self, forKey: .visible)
        try decodeChildren(from: decoder)
        setup()
    }

    open func decodeChildren(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        children = try values.decode([Object].self, forKey: .children)
        for child in children {
            child.parent = self
        }
    }

    // MARK: - Encode

    open func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(position, forKey: .position)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(scale, forKey: .scale)
        try container.encode(visible, forKey: .visible)
        try encodeChildren(to: encoder)
    }

    open func encodeChildren(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(children, forKey: .children)
    }

    // MARK: - Setup

    open func setup() {}

    // MARK: - Compute Bounds

    open func computeBounds() -> Bounds {
        createBounds()
    }

    open func computeLocalBounds() -> Bounds {
        transformBounds(bounds, localMatrix)
    }

    /// Overrides must merge every child's `worldBounds`: reading them is what clears marked
    /// descendants along with this object, which `updateWorldBounds` relies on.
    open func computeWorldBounds() -> Bounds {
        children.reduce(transformBounds(bounds, worldMatrix)) { mergeBounds($0, $1.worldBounds) }
    }

    open func update() {
        onUpdate?()
    }

    /// Encodes this object's GPU work for the frame (compute, generated geometry), after `update()`
    /// and before any pass draws it. Write outputs to slices from `try context.allocate(length:)` so
    /// two encodes before the draws execute never overwrite each other.
    open func encode(in context: EncodingContext) throws {}


    // MARK: - Inserting, Adding, Attaching & Removing

    open func insert(_ child: Object, at: Int, setParent: Bool = true) {
        if !children.contains(where: { $0 === child }) {
            if setParent {
                child.parent = self
            }
            _children.insert(child, at: at)
            registerAsContainer(of: child)
            childrenDidChange()
        }
    }

    open func add(_ child: Object, _ setParent: Bool = true) {
        guard children.firstIndex(of: child) == nil, child != self else { return }

        if setParent {
            child.removeFromParent()
            child.parent = self
        }

        _children.append(child)
        registerAsContainer(of: child)
        childrenDidChange()
    }

    open func attach(_ child: Object) {
        add(child, false)
    }

    open func add(_ objects: [Object], _ setParent: Bool = true) {
        for obj in objects {
            add(obj, setParent)
        }
    }

   

    open func remove(_ child: Object) {
        guard let childIndex = children.firstIndex(of: child) else { return }

        if child.parent === self {
            child.parent = nil
        }

        _children.remove(at: childIndex)
        if !_children.contains(where: { $0 === child }) {
            child.removeContainer(ObjectIdentifier(self))
        }
        childrenDidChange()
    }

    open func removeFromParent() {
        parent?.remove(self)
    }

    open func removeAll() {
        for child in children {
            remove(child)
        }
    }

    // MARK: - Recursive Scene Graph Functions

    public func apply(recursive: Bool = true, _ fn: (_ object: Object) -> Void) {
        fn(self)
        if recursive {
            for child in children {
                child.apply(recursive: recursive, fn)
            }
        }
    }

    public func traverse(_ fn: (_ object: Object) -> Void) {
        for child in children {
            fn(child)
            child.traverse(fn)
        }
    }

    public func traverseVisible(_ fn: (_ object: Object) -> Void) {
        for child in children where child.visible {
            fn(child)
            child.traverseVisible(fn)
        }
    }

    public func traverseAncestors(_ fn: (_ object: Object) -> Void) {
        if let parent {
            fn(parent)
            parent.traverseAncestors(fn)
        }
    }

    // MARK: - Root

    public func getRoot() -> Object? {
        if let parent {
            return parent.getRoot()
        } else {
            return self
        }
    }

    // MARK: - Children

    public func getChildren(_ recursive: Bool = true) -> [Object] {
        var results: [Object] = []
        for child in children {
            results.append(child)
            if recursive {
                results.append(contentsOf: child.getChildren(recursive))
            }
        }
        return results
    }

    public func getChild(_ name: String, _ recursive: Bool = true) -> Object? {
        for child in children {
            if child.label == name {
                return child
            } else if recursive, let found = child.getChild(name, recursive) {
                return found
            }
        }
        return nil
    }

    public func getChildById(_ id: String, _ recursive: Bool = true) -> Object? {
        for child in children where child.id == id {
            return child
        }
        if recursive {
            for child in children {
                if let found = child.getChildById(id, recursive) {
                    return found
                }
            }
        }
        return nil
    }

    public func getChildrenByName(_ name: String, _ recursive: Bool = true) -> [Object] {
        var results = [Object]()
        getChildrenByName(name, recursive, &results)
        return results
    }

    func getChildrenByName(_ name: String, _ recursive: Bool = true, _ results: inout [Object]) {
        for child in children {
            if child.label == name {
                results.append(child)
            } else if recursive {
                child.getChildrenByName(name, recursive, &results)
            }
        }
    }

    // MARK: - isVisible

    public var isVisible: Bool {
        if let parent {
            return parent.isVisible && visible
        } else {
            return visible
        }
    }

    // MARK: - isLight

    public var isLight: Bool {
        if let parent {
            return parent.isLight || (self is Light)
        } else {
            return self is Light
        }
    }

    public func setFrom(object: Object, world: Bool = false) {
        if world {
            worldPosition = object.worldPosition
            worldOrientation = object.worldOrientation
            worldScale = object.worldScale
        } else {
            position = object.position
            orientation = object.orientation
            scale = object.scale
        }
    }

    // MARK: - Look At

    public func lookAt(target: simd_float3, up: simd_float3 = Satin.worldUpDirection, local: Bool = true) {
        if local {
            localMatrix = lookAtMatrix3f(position, target, up)
        } else {
            worldMatrix = lookAtMatrix3f(worldPosition, target, up)
        }
    }

    // MARK: - Intersections

    open func intersects(ray: Ray) -> Bool {
        return rayBoundsIntersect(ray, worldBounds)
    }

    open func intersect(
        ray: Ray,
        intersections: inout [RaycastResult],
        options: RaycastOptions
    ) -> Bool {
        guard visible || options.invisible, intersects(ray: ray), options.recursive else { return false }

        var results = [RaycastResult]()

        for child in children {
            if child.intersect(
                ray: ray,
                intersections: &results,
                options: options
            ) && options.first {
                intersections.append(contentsOf: results)
                return true
            }
        }

        intersections.append(contentsOf: results)

        return results.count > 0
    }

    // MARK: - Conversion Utilities

    /// Converts a position from the local space of the Object on which you called this method to the local space of a reference Object.
    /// - Parameters:
    ///   - position: The position given in the local space of the Object.
    ///   - referenceObject: The Object that defines a frame of reference. Set this to nil to indicate world space.
    /// - Returns: The position specified relative to referenceObject.
    public func convert(position: simd_float3, to referenceObject: Object?) -> simd_float3 {
        let worldSpacePosition = simd_make_float3((worldMatrix * translationMatrix3f(position)).columns.3)
        if let referenceObject = referenceObject {
            return simd_make_float3((referenceObject.worldMatrixInverse * translationMatrix3f(worldSpacePosition)).columns.3)
        } else {
            return worldSpacePosition
        }
    }

    /// Converts a position from the local space of a reference Object to the local space of the Object on which you called this method.
    /// - Parameters:
    ///   - position: The position specified relative to referenceObject.
    ///   - referenceObject: The Object that defines a frame of reference. Set this to nil to indicate world space.
    /// - Returns: The position given in the local space of the Object.
    public func convert(position: simd_float3, from referenceObject: Object?) -> simd_float3 {
        var worldSpacePosition = position
        if let referenceObject = referenceObject {
            worldSpacePosition = simd_make_float3((referenceObject.worldMatrix * translationMatrix3f(position)).columns.3)
        }
        return simd_make_float3((worldMatrixInverse * translationMatrix3f(worldSpacePosition)).columns.3)
    }

    /// Converts a direction vector from the local space of the Object on which you called this method to the local space of a reference Object.
    /// - Parameters:
    ///   - direction: The direction vector given in the local space of the Object.
    ///   - referenceObject: The Object that defines a frame of reference. Set this to nil to indicate world space.
    /// - Returns: The direction vector specified relative to referenceObject.
    public func convert(direction: simd_float3, to referenceObject: Object?) -> simd_float3 {
        let worldSpaceDirection = worldOrientation.act(direction)

        if let referenceObject = referenceObject {
            return referenceObject.worldOrientation.inverse.act(worldSpaceDirection)
        } else {
            return worldSpaceDirection
        }
    }

    /// Converts a direction vector from the local space of a reference Object to the local space of the Object on which you called this method.
    /// - Parameters:
    ///   - direction: The direction vector specified relative to referenceObject.
    ///   - referenceObject: The Object that defines a frame of reference. Set this to nil to indicate world space.
    /// - Returns: The direction vector given in the local space of the Object.
    public func convert(direction: simd_float3, from referenceObject: Object?) -> simd_float3 {
        var worldSpaceDirection = direction
        if let referenceObject = referenceObject {
            worldSpaceDirection = referenceObject.worldOrientation.act(direction)
        }
        return worldOrientation.inverse.act(worldSpaceDirection)
    }
}

// MARK: - Equatable

extension Object: Equatable {
    public static func == (lhs: Object, rhs: Object) -> Bool {
        lhs === rhs
    }
}

extension Object: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
