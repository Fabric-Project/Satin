//
//  SlugTextMesh.swift
//
//
//  Created by OpenAI on 4/25/26.
//

import Foundation
import simd

public final class SlugTextMesh: Mesh {
    public var font: SlugFontAtlas {
        get {
            (geometry as! SlugTextGeometry).font
        }
        set {
            (geometry as! SlugTextGeometry).font = newValue
            syncMaterialTextures()
        }
    }

    public var text: String {
        get {
            (geometry as! SlugTextGeometry).text
        }
        set {
            (geometry as! SlugTextGeometry).text = newValue
        }
    }

    public init(context: Context, label: String = "SlugTextMesh", geometry: SlugTextGeometry, material: SlugTextMaterial?) {
        super.init(context: context, label: label, geometry: geometry, material: material)
        syncMaterialTextures()
    }

    public convenience init(
        context: Context,
        text: String,
        fontName: String,
        color: simd_float4 = .one
    ) {
        let atlas = SlugFontAtlas.shared(context: context, fontName: fontName)
        let geometry = SlugTextGeometry(context: context, text: text, font: atlas)
        let material = SlugTextMaterial(
            context: context,
            color: color,
            curveTexture: atlas.curveTexture,
            bandTexture: atlas.bandTexture
        )
        self.init(context: context, geometry: geometry, material: material)
    }

    override public func update() {
        syncMaterialTextures()
        super.update()
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    private func syncMaterialTextures() {
        guard let material = material as? SlugTextMaterial else { return }
        let font = (geometry as! SlugTextGeometry).font
        material.curveTexture = font.curveTexture
        material.bandTexture = font.bandTexture
    }
}
