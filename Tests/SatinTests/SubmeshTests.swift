//
//  SubmeshTests.swift
//
//
//  Created by Toby Harris on 10/13/26.
//

import Satin
import XCTest

class SubmeshTests: XCTestCase {
    /// A submesh's material is set up when the submesh joins its mesh, as the
    /// model loader adds one for each material in a model. Unset, the
    /// material has no depth stencil state, and binding it for a draw hands
    /// Metal nil.
    func testAddedSubmeshMaterialIsSetUp() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        let geometry = BoxGeometry(context: context)
        let mesh = Mesh(context: context, geometry: geometry, material: nil)
        let elementBuffer = try XCTUnwrap(geometry.elementBuffer)
        let material = BasicColorMaterial(context: context)

        mesh.addSubmesh(Submesh(parent: mesh, elementBuffer: elementBuffer, material: material))

        XCTAssertNotNil(material.depthStencilState)
    }
}
