//
//  InstancingRenderer.swift
//  Example
//
//  Created by Reza Ali on 8/17/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

final class CustomInstancingRenderer: BaseRenderer {
    final class InstanceMaterial: SourceMaterial {}

    // MARK: - Paths

    var dataBuffer: MTLBuffer?

    lazy var instanceMaterial: InstanceMaterial = {
        let material = InstanceMaterial(pipelinesURL: pipelinesURL)
        material.onBind = { [unowned self] renderEncoder in
            renderEncoder.setVertexBuffer(self.dataBuffer, offset: 0, index: VertexBufferIndex.Custom0.rawValue)
        }
        return material
    }()

    let camera = OrthographicCamera()

    lazy var mesh = Mesh(geometry: QuadGeometry(), material: instanceMaterial)
    lazy var scene = Object(label: "Scene", [mesh])
    lazy var cameraController = OrthographicCameraController(camera: camera, view: metalView, defaultZoom: 2.0)
    lazy var renderer = Renderer(context: defaultContext)

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    override func setup() {
        setupData()

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    func setupData() {
        var data: [Bool] = []
        do {
            let sequence = try String(contentsOf: dataURL.appendingPathComponent("SARS-CoV-2.txt"), encoding: .utf8)
            for character in sequence {
                switch character {
                case "a":
                    data.append(false)
                    data.append(false)
                case "c":
                    data.append(false)
                    data.append(true)
                case "g":
                    data.append(true)
                    data.append(false)
                case "t":
                    data.append(true)
                    data.append(true)
                default:
                    break
                }
            }
        } catch {
            print(error.localizedDescription)
        }
        guard data.count > 0 else { return }
        dataBuffer = device.makeBuffer(bytes: &data, length: MemoryLayout<simd_bool>.stride * data.count)
        // data.count/2 because we are representing each character a = 0 c = 1 g = 2 t = 3 using two bools (00, 01, 10, 11)
        mesh.instanceCount = data.count / 2
        instanceMaterial.set("Instance Count", Int(data.count / 2))
    }

    override func update() {
        cameraController.update()
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
        cameraController.resize(size)
        renderer.resize(size)
        instanceMaterial.set("Resolution", [size.width, size.height, size.width / size.height])
    }
}
