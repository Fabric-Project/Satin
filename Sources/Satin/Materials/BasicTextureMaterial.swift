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
    public var flipped = false {
        didSet {
            set("Flipped", flipped)
        }
    }

    public required init() {
        super.init()
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        set("Flipped", flipped)
    }

    public init(texture: MTLTexture?, sampler: MTLSamplerState? = nil, flipped: Bool = false) {
        super.init()
        if let texture = texture, texture.textureType != .type2D, texture.textureType != .type2DMultisample {
            fatalError("BasicTextureMaterial expects a 2D texture")
        }
        self.flipped = flipped
        self.texture = texture
        self.sampler = sampler
        set("Flipped", flipped)
    }

    public init(texture: MTLTexture, sampler: MTLSamplerState? = nil) {
        super.init()
        if texture.textureType != .type2D, texture.textureType != .type2DMultisample {
            fatalError("BasicTextureMaterial expects a 2D texture")
        }
        self.texture = texture
        self.sampler = sampler
        set("Flipped", flipped)
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
        sampler = context?.device.makeSamplerState(descriptor: desc)
    }

    public func bindTexture(_ renderEncoder: MTLRenderCommandEncoder) {
        if let texture = texture {
            renderEncoder.setFragmentTexture(texture, index: FragmentTextureIndex.Custom0.rawValue)
        }
    }

    public func bindSampler(_ renderEncoder: MTLRenderCommandEncoder) {
        if let sampler = sampler {
            renderEncoder.setFragmentSamplerState(sampler, index: FragmentSamplerIndex.Custom0.rawValue)
        }
    }

    override public func bind(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        let renderEncoder = renderEncoderState.renderEncoder
        bindTexture(renderEncoder)
        bindSampler(renderEncoder)
        super.bind(
            renderContext: renderContext,
            renderEncoderState: renderEncoderState,
            shadow: shadow
        )
    }
}
