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
