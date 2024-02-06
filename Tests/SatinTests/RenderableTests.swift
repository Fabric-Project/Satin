//
//  RenderableTests.swift
//
//
//  Created by Reza Ali on 3/14/23.
//

import Satin
import XCTest

class RenderableTests: XCTestCase {
    func testShaderCompilation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let label = "BasicColor"
        let shader = SourceShader(
            label: label,
            pipelineURL: getPipelinesMaterialsURL(label)!.appendingPathComponent("Shaders.metal")
        )

        measure {
            shader.context = context
        }
    }
}
