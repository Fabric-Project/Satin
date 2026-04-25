//
//  ARPlaneContainer.swift
//  Example
//
//  Created by Reza Ali on 4/26/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Foundation
import Metal

class ARPlaneMesh: Mesh {
    public var anchor: ARPlaneAnchor {
        didSet {
            updateAnchor()
        }
    }

    public init(label: String, anchor: ARPlaneAnchor, material: Satin.Material) {
        self.anchor = anchor
        let geometry = Geometry()
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: []), for: .Position)
        geometry.addAttribute(Float2BufferAttribute(defaultValue: .zero, data: []), for: .Texcoord)
        super.init(geometry: geometry, material: material)
        self.label = label
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    private func updateAnchor() {
        updateTransform()
        updateGeometry()
    }

    private func updateTransform() {
        worldMatrix = anchor.transform
    }

    private func updateGeometry() {
        guard let positionBuffer = geometry.getAttribute(.Position) as? Float3BufferAttribute,
              let texcoordBuffer = geometry.getAttribute(.Texcoord) as? Float2BufferAttribute else { return }

        positionBuffer.data = anchor.geometry.vertices
        texcoordBuffer.data = anchor.geometry.textureCoordinates

        var elements = anchor.geometry.triangleIndices
        geometry.setElements(ElementBuffer(type: .uint16, data: &elements, count: elements.count, source: elements))
    }
}

#endif
