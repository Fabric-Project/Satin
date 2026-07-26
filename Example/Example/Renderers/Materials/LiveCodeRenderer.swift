//
//  RenderEncoder.swift
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
        override init(context: Context, pipelinesURL: URL, live: Bool = true) {
            super.init(context: context, pipelinesURL: pipelinesURL, live: true)
            self.blending = .alpha
        }

        required init(context: Context) {
            super.init(context: context)
        }

        required init(from decoder: Decoder) throws {
            fatalError("init(from:) has not been implemented")
        }
    }

    var startTime: CFAbsoluteTime = 0.0

    lazy var camera = OrthographicCamera(context: defaultContext)

    lazy var mesh = Mesh(context: defaultContext, geometry: QuadGeometry(context: defaultContext), material: CustomMaterial(context: defaultContext, pipelinesURL: pipelinesURL))
    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])
    lazy var renderer = RenderEncoder(context: defaultContext)

    override var colorPixelFormat: MTLPixelFormat { .rgba16Float }
    override var depthPixelFormat: MTLPixelFormat { .invalid }

    override func setup() throws {
        startTime = getTime()
#if os(macOS)
        openEditor()
#endif

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    override func update() throws {
        // Uniforms are parsed and title cases, i.e. time -> Time, appResolution -> App Resolution, etc
        if let material = mesh.material {
            material.set("Time", Float(getTime() - startTime))
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try renderer.draw(
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
