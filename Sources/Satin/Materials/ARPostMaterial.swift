//
//  ARPostMaterial.swift
//
//
//  Created by Reza Ali on 1/24/24.
//

import Metal
import simd

public class ARPostMaterial: Material {
    public unowned var contentTexture: MTLTexture? {
        didSet {
            set(contentTexture, index: FragmentTextureIndex.Custom0)
        }
    }

    public unowned var cameraGrainTexture: MTLTexture? {
        didSet {
            set(cameraGrainTexture, index: FragmentTextureIndex.Custom1)
        }
    }

    public var contentTextureTransform: simd_float4x4 {
        get {
            get("Content Texture Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4
        }
        set {
            set("Content Texture Transform", newValue)
        }
    }

    private lazy var startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var time: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    init(context: Context, contentTexture: MTLTexture? = nil, cameraGrainTexture: MTLTexture? = nil) {
        self.contentTexture = contentTexture
        self.cameraGrainTexture = cameraGrainTexture
        super.init(context: context)
        configure()
    }

    public required init(context: Context) {
        super.init(context: context)
        configure()
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        configure()
    }

    private func configure() {
        blending = .alpha
        if get("Content Texture Transform") == nil {
            set("Content Texture Transform", matrix_identity_float4x4)
        }
    }

    override public func update() {
        time = CFAbsoluteTimeGetCurrent() - startTime
        set("Time", Float(time))
        if let cameraGrainTexture {
            set("Grain Size", simd_make_float2(Float(cameraGrainTexture.width), Float(cameraGrainTexture.height)))
        }
        super.update()
    }
}
