//
//  TextMesh.swift
//
//
//  Created by Reza Ali on 12/30/23.
//

import Foundation

public final class TextMesh: Mesh {
    public var font: FontAtlas {
        get {
            (geometry as! TextGeometry).font
        }
        set {
            (geometry as! TextGeometry).font = newValue
        }
    }

    public var text: String {
        get {
            (geometry as! TextGeometry).text
        }
        set {
            (geometry as! TextGeometry).text = newValue
        }
    }

    public init(label: String = "TextMesh", geometry: TextGeometry, material: TextMaterial?) {
        super.init(label: label, geometry: geometry, material: material)
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
}
