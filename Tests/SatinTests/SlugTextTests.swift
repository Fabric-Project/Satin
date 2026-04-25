//
//  SlugTextTests.swift
//
//
//  Created by OpenAI on 4/25/26.
//

import Metal
import Satin
import XCTest

final class SlugTextTests: XCTestCase {
    func testSlugTextMaterialCompiles() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let atlas = SlugFontAtlas(context: context, fontName: "Helvetica")
        let geometry = SlugTextGeometry(context: context, text: "SLUG", font: atlas)
        let material = SlugTextMaterial(
            context: context,
            color: .one,
            curveTexture: atlas.curveTexture,
            bandTexture: atlas.bandTexture
        )

        material.vertexDescriptor = geometry.vertexDescriptor
        material.setup()

        XCTAssertNotNil(material.getPipeline(renderContext: context, shadow: false))
    }

    func testSlugTextGeometryProducesIndexedQuads() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let atlas = SlugFontAtlas(context: context, fontName: "Helvetica")
        let geometry = SlugTextGeometry(context: context, text: "AB", font: atlas)
        geometry.update()

        XCTAssertGreaterThan(geometry.vertexCount, 0)
        XCTAssertGreaterThan(geometry.indexCount, 0)
        XCTAssertEqual(geometry.vertexCount % 4, 0)
        XCTAssertEqual(geometry.indexCount % 6, 0)
    }
}
