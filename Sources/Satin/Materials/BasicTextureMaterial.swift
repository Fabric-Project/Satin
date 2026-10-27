//
//  BasicTextureMaterial.swift
//  Satin
//
//  Created by Reza Ali on 4/19/20.
//

import Metal

open class BasicTextureMaterial: BasicColorMaterial {
    public var texture: MTLTexture?
    public var sampler: MTLSamplerState?
    open var textureTransform: simd_float4x4 {
        get {
            get("Texture Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4
        }
        set {
            set("Texture Transform", newValue)
        }
    }

    public var flipped = false {
        didSet {
            textureTransform = flipped ? .textureVerticalFlip : matrix_identity_float4x4
        }
    }

    public required init(context: Context) {
        super.init(context: context)
        initializeTextureTransform()
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        initializeTextureTransform(flipped ? .textureVerticalFlip : matrix_identity_float4x4)
    }

    public init(context: Context, texture: MTLTexture?, sampler: MTLSamplerState? = nil, flipped: Bool = false) {
        super.init(context: context)
        if let texture = texture, texture.textureType != .type2D, texture.textureType != .type2DMultisample {
            fatalError("BasicTextureMaterial expects a 2D texture")
        }
        self.flipped = flipped
        self.texture = texture
        if let sampler { self.sampler = sampler }
        initializeTextureTransform(flipped ? .textureVerticalFlip : matrix_identity_float4x4)
    }

    public init(context: Context, texture: MTLTexture, sampler: MTLSamplerState? = nil) {
        super.init(context: context)
        if texture.textureType != .type2D, texture.textureType != .type2DMultisample {
            fatalError("BasicTextureMaterial expects a 2D texture")
        }
        self.texture = texture
        if let sampler { self.sampler = sampler }
        initializeTextureTransform()
    }

    override public func setup() {
        super.setup()
        setupSampler()
    }

    public func setupSampler() {
        guard sampler == nil else { return }
        let desc = MTLSamplerDescriptor()
        desc.label = label.titleCase
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .linear
        sampler = context.device.makeSamplerState(descriptor: desc)
    }

    private func initializeTextureTransform(_ transform: simd_float4x4 = matrix_identity_float4x4) {
        if get("Texture Transform") == nil {
            set("Texture Transform", transform)
        }
        else {
            textureTransform = transform
        }
    }

    override public func draw(in context: MaterialDrawContext) throws {
        if let texture {
            context.setFragmentTexture(texture, index: .Custom0)
        }
        if let sampler {
            context.setFragmentSamplerState(sampler, index: .Custom0)
        }
        try super.draw(in: context)
    }
}
