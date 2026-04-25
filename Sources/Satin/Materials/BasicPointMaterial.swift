//
//  BasicPointMaterial.swift
//  Satin
//
//  Created by Reza Ali on 6/28/20.
//

import Metal
import simd

open class BasicPointMaterial: Material {
    public var color: simd_float4 {
        get {
            get("Color", as: Float4Parameter.self)!.value
        }
        set {
            set("Color", newValue)
        }
    }

    public var pointSize: Float = 2.0 {
        didSet {
            updateSize()
        }
    }

    public var contentScale: Float = 1.0 {
        didSet {
            updateSize()
        }
    }

    public init(color: simd_float4, size: Float, blending: Blending = .alpha, depthWriteEnabled: Bool = true, depthCompareFunction: MTLCompareFunction = .greaterEqual) {
        super.init()

        self.blending = blending
        self.depthWriteEnabled = depthWriteEnabled
        self.depthCompareFunction = depthCompareFunction

        self.color = color
        pointSize = size
        updateSize()
    }

    public required init() {
        super.init()

        blending = .alpha

        color = .one
        pointSize = 2.0
        updateSize()
    }

    private func updateSize() {
        let size = pointSize * contentScale
        set("Size", size)
        set("Size Half", size * 0.5)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
