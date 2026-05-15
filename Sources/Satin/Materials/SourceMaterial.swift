//
//  SourceMaterial.swift
//  Satin
//
//  Created by Reza Ali on 12/31/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation

open class SourceMaterial: Material {
    override var supportsAlphaOrderIndependentTransparency: Bool {
        source?.contains("SATIN_ALPHA_OIT_ENABLED") == true
    }

    public enum CodingKeys: String, CodingKey {
        case pipelineURL
    }

    public var pipelineURL: URL
    public var live: Bool = false {
        didSet {
            if let shader = shader as? SourceShader {
                shader.live = live
            }
        }
    }

    public var source: String? {
        guard let shader = shader as? SourceShader else { return nil }
        return shader.source
    }

    public init(context: Context, pipelineURL: URL, live: Bool = false) {
        self.pipelineURL = pipelineURL
        self.live = live
        super.init(context: context)
    }

    public init(context: Context, pipelinesURL: URL, live: Bool = false) {
        if pipelinesURL.pathExtension == "metal" {
            pipelineURL = pipelinesURL
        } else {
            // Compute the label prefix before super.init (same logic as Material.prefix)
            var labelPrefix = String(describing: type(of: self)).replacingOccurrences(of: "Material", with: "")
            if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != labelPrefix {
                labelPrefix = labelPrefix.replacingOccurrences(of: bundleName, with: "")
            }
            labelPrefix = labelPrefix.replacingOccurrences(of: ".", with: "")
            pipelineURL = pipelinesURL.appendingPathComponent(labelPrefix).appendingPathComponent("Shaders.metal")
        }
        self.live = live
        super.init(context: context)
    }

    override open func createShader() -> Shader {
        let shader = SourceShader(context: context, label: label, pipelineURL: pipelineURL)
        shader.live = live
        shader.blending = blending
        return shader
    }

    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pipelineURL = try values.decode(URL.self, forKey: .pipelineURL)
        try super.init(from: decoder)
    }

    override open func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pipelineURL, forKey: .pipelineURL)
    }

    public required init(context: Context) {
        fatalError("Please specify a pipeline url to use SourceMaterial")
    }

    override open func clone(context: Context) -> Material {
        let clone = SourceMaterial(context: context, pipelineURL: pipelineURL, live: live)
        clone.isClone = true
        cloneProperties(clone: clone)
        return clone
    }
}
