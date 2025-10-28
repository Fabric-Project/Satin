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

#if SWIFT_PACKAGE
import SatinCore
#endif

open class Object: Codable {
    public let idPublisher = PassthroughSubject<String, Never>()
    var id: String = UUID().uuidString {
        didSet {
            idPublisher.send(id)
        }
    }

    public let labelPublisher = PassthroughSubject<String, Never>()
    public var label = "Object" {
        didSet {
            labelPublisher.send(label)
        }
    }

    public let visiblePublisher = PassthroughSubject<Bool, Never>()
    public var visible = true {
        didSet {
            visiblePublisher.send(visible)
        }
    }

    open var context: Context? = nil {
        didSet {
            if let context, context != oldValue {
                setup()
                //objectWillChange.send()
            }
        }
    }

    // MARK: - Position

    public var position: simd_float3 = .zero {
        didSet {
            _translationMatrix.clear()

            updateLocalMatrix = true

            positionPublisher.send(self)
        }
    }

    var _worldPosition = ValueCache<simd_float3>()
    public var worldPosition: simd_float3 {
        get {
            _worldPosition.get {
                simd_make_float3(worldMatrix.columns.3)
            }
        }
        set {
            if let parent = parent {
                position = simd_make_float3(parent.worldMatrixInverse * simd_make_float4(newValue, 1.0))
            } else {
                position = newValue
            }
        }
    }

    var _translationMatrix = ValueCache<matrix_float4x4>()
    public var translationMatrix: matrix_float4x4 {
        _translationMatrix.get { translationMatrix3f(position) }
    }

    // MARK: - Orientation

    public var orientation = simd_quatf(matrix_identity_float4x4) {
        didSet {
            _rotationMatrix.clear()

            _rightDirection.clear()
            _upDirection.clear()
            _forwardDirection.clear()

            updateLocalMatrix = true

            orientationPublisher.send(self)
        }
    }

    var _worldOrientation = ValueCache<simd_quatf>()
    public var worldOrientation: simd_quatf {
        get {
            _worldOrientation.get {
                let ws = worldScale
                let wm = worldMatrix
                let c0 = wm.columns.0
                let c1 = wm.columns.1
                let c2 = wm.columns.2
                let x = simd_make_float3(c0.x, c0.y, c0.z) / ws.x
                let y = simd_make_float3(c1.x, c1.y, c1.z) / ws.y
                let z = simd_make_float3(c2.x, c2.y, c2.z) / ws.z
                return simd_quatf(simd_float3x3(columns: (x, y, z)))
            }
        }
        set {
            if let parent = parent {
                orientation = parent.worldOrientation.inverse * newValue
            } else {
                orientation = newValue
            }
        }
    }

    var _rotationMatrix = ValueCache<matrix_float4x4>()
    public var rotationMatrix: matrix_float4x4 {
        _rotationMatrix.get { matrix_float4x4(orientation) }
    }

    // MARK: - Scale

    public var scale: simd_float3 = .one {
        didSet {
            _scaleMatrix.clear()

            updateLocalMatrix = true

            scalePublisher.send(self)
        }
    }

    var _worldScale = ValueCache<simd_float3>()
    public var worldScale: simd_float3 {
        get {
            _worldScale.get {
                let wm = worldMatrix
                let sx = wm.columns.0
                let sy = wm.columns.1
                let sz = wm.columns.2
                return simd_make_float3(length(sx), length(sy), length(sz))
            }
        }
        set {
            if let parent = parent {
                scale = newValue / parent.worldScale
            } else {
                scale = newValue
            }
        }
    }

    var _scaleMatrix = ValueCache<matrix_float4x4>()
    public var scaleMatrix: matrix_float4x4 {
        _scaleMatrix.get {
            scaleMatrix3f(scale)
        }
    }

    // MARK: - Local Matrix

    var _localMatrix = ValueCache<matrix_float4x4>()
    public var localMatrix: matrix_float4x4 {
        get {
            _localMatrix.get {
                simd_mul(simd_mul(translationMatrix, rotationMatrix), scaleMatrix)
            }
        }
        set {
            position = simd_make_float3(newValue.columns.3)
            let sx = newValue.columns.0
            let sy = newValue.columns.1
            let sz = newValue.columns.2
            scale = simd_make_float3(simd_length(sx), simd_length(sy), simd_length(sz))
            let rx = simd_make_float3(sx) / scale.x
            let ry = simd_make_float3(sy) / scale.y
            let rz = simd_make_float3(sz) / scale.z
            orientation = simd_quatf(simd_float3x3(rx, ry, rz))
        }
    }

    var _localMatrixInverse = ValueCache<matrix_float4x4>()
    public var localMatrixInverse: matrix_float4x4 {
        _localMatrixInverse.get {
            localMatrix.inverse
        }
    }

    public var updateLocalMatrix = true {
        didSet {
            if updateLocalMatrix {
                updateLocalBounds = true

                _localMatrix.clear()
                _localMatrixInverse.clear()

                updateLocalMatrix = false

                updateWorldMatrix = true
            }
        }
    }

    // MARK: - World Matrix

    var _worldMatrix = ValueCache<matrix_float4x4>()
    public var worldMatrix: matrix_float4x4 {
        get {
            _worldMatrix.get {
                if let parent = parent {
                    return simd_mul(parent.worldMatrix, localMatrix)
                } else {
                    return localMatrix
                }
            }
        }
        set {
            if let parent = parent {
                localMatrix = parent.worldMatrixInverse * newValue
            } else {
                localMatrix = newValue
            }
        }
    }

    var _worldMatrixInverse = ValueCache<matrix_float4x4>()
    public var worldMatrixInverse: matrix_float4x4 {
        _worldMatrixInverse.get {
            worldMatrix.inverse
        }
    }

    var updateWorldMatrix = true {
        didSet {
            if updateWorldMatrix {
                updateWorldBounds = true

                _normalMatrix.clear()
                _worldMatrix.clear()
                _worldMatrixInverse.clear()

                _worldPosition.clear()
                _worldOrientation.clear()
                _worldScale.clear()

                _worldRightDirection.clear()
                _worldUpDirection.clear()
                _worldForwardDirection.clear()

                transformPublisher.send(self)

                updateWorldMatrix = false

                for child in children {
                    child.updateWorldMatrix = true
                }
            }
        }
    }

    // MARK: - Normal Bounds

    var _normalMatrix = ValueCache<matrix_float3x3>()
    public var normalMatrix: matrix_float3x3 {
        _normalMatrix.get {
            let n = worldMatrixInverse.transpose
            return simd_matrix(simd_make_float3(n.columns.0), simd_make_float3(n.columns.1), simd_make_float3(n.columns.2))
        }
    }

    // MARK: - Bounds

    public var updateBounds = true {
        didSet {
            if updateBounds {
                _updateBounds = true
                boundsPublisher.send(self)
                parent?.updateBounds = true
                updateBounds = false
            }
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

    public var updateLocalBounds = true {
        didSet {
            if updateLocalBounds {
                _updateLocalBounds = true
                localBoundsPublisher.send(self)
                parent?.updateLocalBounds = true
                updateLocalBounds = false
            }
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

     var updateWorldBounds = true {
        didSet {
            if updateWorldBounds {
                _updateWorldBounds = true
                worldBoundsPublisher.send(self)
                parent?.updateWorldBounds = true
                updateWorldBounds = false
            }
        }
    }

    var _updateWorldBounds = true

    var _worldBounds = createBounds()
    public var worldBounds: Bounds {
        if _updateWorldBounds {
            _worldBounds = computeWorldBounds()
            _updateWorldBounds = false
        }
        return _worldBounds
    }

    // MARK: - Directions

    var _forwardDirection = ValueCache<simd_float3>()
    public var forwardDirection: simd_float3 {
        _forwardDirection.get {
            simd_normalize(orientation.act(Satin.worldForwardDirection))
        }
    }

    var _upDirection = ValueCache<simd_float3>()
    public var upDirection: simd_float3 {
        _upDirection.get {
            simd_normalize(orientation.act(Satin.worldUpDirection))
        }
    }

    var _rightDirection = ValueCache<simd_float3>()
    public var rightDirection: simd_float3 {
        _rightDirection.get {
            simd_normalize(orientation.act(Satin.worldRightDirection))
        }
    }

    // MARK: - World Directions

    var _worldForwardDirection = ValueCache<simd_float3>()
    public var worldForwardDirection: simd_float3 {
        _worldForwardDirection.get {
            simd_normalize(worldOrientation.act(Satin.worldForwardDirection))
        }
    }

    var _worldUpDirection = ValueCache<simd_float3>()
    public var worldUpDirection: simd_float3 {
        _worldUpDirection.get {
            simd_normalize(worldOrientation.act(Satin.worldUpDirection))
        }
    }

    var _worldRightDirection = ValueCache<simd_float3>()
    public var worldRightDirection: simd_float3 {
        _worldRightDirection.get {
            simd_normalize(worldOrientation.act(Satin.worldRightDirection))
        }
    }

    // MARK: - Parent & Children

     weak var parent: Object? {
        didSet {
            updateWorldMatrix = true
        }
    }

    public var children: [Object] = [] {
        didSet {
            updateLocalBounds = true
        }
    }

    // MARK: - OnUpdate Hook

    public var onUpdate: (() -> Void)?

    // MARK: - Publishers

    public let positionPublisher = PassthroughSubject<Object, Never>()
    public let scalePublisher = PassthroughSubject<Object, Never>()
    public let orientationPublisher = PassthroughSubject<Object, Never>()

    public let boundsPublisher = PassthroughSubject<Object, Never>()
    public let localBoundsPublisher = PassthroughSubject<Object, Never>()
    public let worldBoundsPublisher = PassthroughSubject<Object, Never>()

    public let transformPublisher = PassthroughSubject<Object, Never>()

    public let childAddedPublisher = PassthroughSubject<Object, Never>()
    public let childRemovedPublisher = PassthroughSubject<Object, Never>()

    private var childAddedSubscriptions: [Object: AnyCancellable] = [:]
    private var childRemovedSubscriptions: [Object: AnyCancellable] = [:]

    // MARK: - Init

    public init() {}

    public init(label: String = "Object", visible: Bool = true, _ children: [Object] = []) {
        self.label = label
        self.visible = visible
        for child in children {
            add(child)
        }
    }

    // MARK: - Deinit

    deinit {}

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
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = try values.decode(String.self, forKey: .label)
        position = try values.decode(simd_float3.self, forKey: .position)
        scale = try values.decode(simd_float3.self, forKey: .scale)
        orientation = try values.decode(simd_quatf.self, forKey: .orientation)
        visible = try values.decode(Bool.self, forKey: .visible)
        try decodeChildren(from: decoder)
    }

    open func decodeChildren(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        children = try values.decode([Object].self, forKey: .children)
        for child in children {
            child.parent = self
            child.context = context
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

    open func computeWorldBounds() -> Bounds {
        children.reduce(transformBounds(bounds, worldMatrix)) { mergeBounds($0, $1.worldBounds) }
    }

    open func update() {
        onUpdate?()
    }

    open func encode(_ commandBuffer: MTLCommandBuffer) {}

    open func update(renderContext: Context, camera: Camera, viewport: simd_float4, index: Int) {}

    // MARK: - Inserting, Adding, Attaching & Removing

    open func insert(_ child: Object, at: Int, setParent: Bool = true) {
        if !children.contains(where: { $0 === child }) {
            if setParent {
                child.parent = self
            }
            child.context = context
            children.insert(child, at: at)
        }
    }

    open func add(_ child: Object, _ setParent: Bool = true) {
        guard children.firstIndex(of: child) == nil, child != self else { return }

        if setParent {
            child.removeFromParent()
            child.parent = self
        }

        child.context = context

        children.append(child)
        childAddedPublisher.send(child)

        childAddedSubscriptions[child] = child.childAddedPublisher.sink { [weak self] subchild in
            self?.childAddedPublisher.send(subchild)
        }

        childRemovedSubscriptions[child] = child.childRemovedPublisher.sink { [weak self] subchild in
            self?.childRemovedPublisher.send(subchild)
        }
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

        childRemovedPublisher.send(child)

        if child.parent === self {
            child.parent = nil
        }

        children.remove(at: childIndex)

        _ = childAddedSubscriptions.removeValue(forKey: child)

        _ = childRemovedSubscriptions.removeValue(forKey: child)
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
