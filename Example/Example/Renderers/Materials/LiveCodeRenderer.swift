//
//  Renderer.swift
//  LiveCode-macOS
//
//  Created by Reza Ali on 6/1/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

final class LiveCodeRenderer: BaseRenderer {
    // Material names must not be the target name, i.e. LiveCodeMaterial won't work

    final class CustomMaterial: SourceMaterial {
        override init(pipelinesURL: URL, live: Bool = true) {
            super.init(pipelinesURL: pipelinesURL, live: true)
            self.blending = .alpha
        }

        required init(from decoder: Decoder) throws {
            fatalError("init(from:) has not been implemented")
        }

        required init() {
            fatalError("init() has not been implemented")
        }
    }

    var startTime: CFAbsoluteTime = 0.0

    let camera = OrthographicCamera()

    lazy var mesh = Mesh(geometry: QuadGeometry(), material: CustomMaterial(pipelinesURL: pipelinesURL))
    lazy var scene = Object(label: "Scene", [mesh])
    lazy var renderer = Renderer(context: defaultContext)

    override var colorPixelFormat: MTLPixelFormat { .rgba16Float }
    override var depthPixelFormat: MTLPixelFormat { .invalid }

    override func setup() {
        startTime = getTime()
#if os(macOS)
        openEditor()
#endif

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    override func update() {
        // Uniforms are parsed and title cases, i.e. time -> Time, appResolution -> App Resolution, etc
        if let material = mesh.material {
            material.set("Time", Float(getTime() - startTime))
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        if let material = mesh.material {
            let res = simd_make_float3(size.width, size.height, size.width / size.height)
            material.set("App Resolution", res)
        }
    }
}
