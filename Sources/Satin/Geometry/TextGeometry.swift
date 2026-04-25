//
//  SDFTextGeometry.swift
//
//
//  Created by Reza Ali on 12/30/23.
//

import CoreText
import Foundation
import simd

public final class TextGeometry: Geometry {
    public var font: FontAtlas {
        didSet {
            _updateData = true
        }
    }

    public var text: String {
        didSet {
            if text != oldValue {
                _updateData = true
            }
        }
    }

    private var _updateData: Bool = true

    private var positions: [simd_float3] = []
    private let positionBuffer = Float3BufferAttribute(defaultValue: .zero, data: [])

    private var texcoords: [simd_float2] = []
    private let texcoordBuffer = Float2BufferAttribute(defaultValue: .zero, data: [])

    private var indices: [UInt32] = []
    private let indexElementBuffer = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)

    public init(text: String, font: FontAtlas) {
        self.text = text
        self.font = font
        super.init()

        addAttribute(positionBuffer, for: .Position)
        addAttribute(texcoordBuffer, for: .Texcoord)
        setElements(indexElementBuffer)

        updateGeometryData()
    }

    public func updateData() {
        let fontSize = Float(font.size)
        let fontWidth = Float(font.width)
        let fontHeight = Float(font.height)

        var totalAdvance: Float = 0
        var maxHeight: Float = fontSize
        for char in text {
            if let character = font.characters[String(char)] {
                totalAdvance += character.advance
                maxHeight = max(maxHeight, character.height)
            }
        }

        // Center the text at the origin
        var x = -totalAdvance * 0.5
        let y = -fontSize * 0.5

        indices.removeAll(keepingCapacity: true)
        texcoords.removeAll(keepingCapacity: true)
        positions.removeAll(keepingCapacity: true)

        var index: UInt32 = 0

        for char in text {
            guard let c = font.characters[String(char)] else { continue }
            if char.isWhitespace {
                x += c.advance
            }
            else {
                // p0 --- p1
                // | \     |
                // |   \   |
                // |     \ |
                // p2 --- p3

                let leftX = x - c.originX
                let rightX = x - c.originX + c.width

                let botY = y + c.originY
                let topY = y + c.originY - c.height

                let leftU = c.x / fontWidth
                let rightU = leftU + (c.width / fontWidth)

                let botV = c.y / fontHeight
                let topV = botV + (c.height / fontHeight)

                let p0 = simd_make_float3(leftX, topY, 0.0)
                let t0 = simd_make_float2(leftU, topV)

                let p1 = simd_make_float3(rightX, topY, 0.0)
                let t1 = simd_make_float2(rightU, topV)

                let p2 = simd_make_float3(leftX, botY, 0.0)
                let t2 = simd_make_float2(leftU, botV)

                let p3 = simd_make_float3(rightX, botY, 0.0)
                let t3 = simd_make_float2(rightU, botV)

                positions.append(contentsOf: [p0, p1, p2, p3])
                texcoords.append(contentsOf: [t0, t1, t2, t3])

                let i0 = index
                let i1 = index + 1
                let i2 = index + 2
                let i3 = index + 3

                indices.append(contentsOf: [i0, i3, i2, i0, i1, i3])

                index += 4

                x += c.advance
            }
        }

        texcoordBuffer.data = texcoords
        positionBuffer.data = positions
        indexElementBuffer.updateData(data: &indices, count: indices.count, source: indices)
    }

    func updateGeometryData() {
        if _updateData {
            updateData()
            _updateData = false
        }
    }

    override public func setup() {
        updateGeometryData()
        super.setup()
    }

    override public func update() {
        updateGeometryData()
        super.update()
    }
}
