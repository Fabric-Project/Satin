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

class MatcapRenderer: BaseRenderer {
    override var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    var scene = Object(label: "Scene")

    lazy var matcapTexture: MTLTexture? = {
        // from https://github.com/nidorx/matcaps
        let fileName = "8A6565_2E214D_D48A5F_ADA59C.png"
        let loader = MTKTextureLoader(device: device)
        do {
            return try loader.newTexture(URL: self.texturesURL.appendingPathComponent(fileName), options: [
                MTKTextureLoader.Option.SRGB: false,
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically
            ])
        } catch {
            print(error)
            return nil
        }
    }()

    let camera = PerspectiveCamera(position: [0.0, 0.0, 8.0], near: 0.001, far: 100.0, fov: 45)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

#if targetEnvironment(simulator)
    override var sampleCount: Int { 1 }
#else
    override var sampleCount: Int { 4 }
#endif

    override func setup() {
        loadModel()
        loadKnot()

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    deinit {
        cameraController.disable()
    }

    func loadModel() {
        let asset = MDLAsset(url: modelsURL.appendingPathComponent("Suzanne").appendingPathComponent("Suzanne.obj"))

        let geometry = Geometry()
        let object0 = asset.object(at: 0)
        if let object = object0 as? MDLMesh {
            object.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
            let descriptor = object.vertexDescriptor

            if object.vertexBuffers.count == 1, let vertexBuffer = object.vertexBuffers.first { // interleaved
                let count = object.vertexCount
                let stride = vertexBuffer.length / count
                let data = vertexBuffer.map().bytes

                let buffer = InterleavedBuffer(
                    index: .Vertices,
                    data: data,
                    stride: stride,
                    count: count,
                    source: vertexBuffer
                )

                for index in VertexAttributeIndex.allCases {
                    if let attribute = descriptor.attributeNamed(index.mdlName) {
                        let offset = attribute.offset
                        switch attribute.format {
                            case .float3:
                                geometry.addAttribute(
                                    Float3InterleavedBufferAttribute(
                                        parent: buffer,
                                        offset: offset
                                    ), for: index
                                )
                            case .float2:
                                geometry.addAttribute(
                                    Float2InterleavedBufferAttribute(
                                        parent: buffer,
                                        offset: offset
                                    ), for: index
                                )
                            case .float4:
                                geometry.addAttribute(
                                    Float4InterleavedBufferAttribute(
                                        parent: buffer,
                                        offset: offset
                                    ), for: index
                                )
                            case .float:
                                geometry.addAttribute(
                                    FloatInterleavedBufferAttribute(
                                        parent: buffer,
                                        offset: offset
                                    ), for: index
                                )
                            default:
                                fatalError("Format not supported")
                        }
                    }
                }
            } else { // seperate buffers for each attribute
            }

            guard let submeshes = object.submeshes, let first = submeshes.firstObject, let sub: MDLSubmesh = first as? MDLSubmesh else { return }

            let indexBuffer = sub.indexBuffer(asIndexType: .uInt32)
            geometry.setElements(
                ElementBuffer(
                    type: .uint32,
                    data: indexBuffer.map().bytes,
                    count: sub.indexCount,
                    source: indexBuffer
                )
            )
        }

        scene.add(
            Mesh(label: "Suzanne", geometry: geometry, material: MatCapMaterial(texture: matcapTexture!))
        )
    }

    func loadKnot() {
        let twoPi = Float.pi * 2.0
        let geometry = ParametricGeometry(rangeU: 0.0...twoPi, rangeV: 0.0...twoPi, resolution: [300, 16], generator: { u, v in
            let R: Float = 1.0
            let r: Float = 0.25
            let c: Float = 0.05
            let q: Float = 2.0
            let p: Float = 3.0
            return torusKnotGenerator(u, v, R, r, c, q, p)
        })

        let mesh = Mesh(geometry: geometry, material: MatCapMaterial(texture: matcapTexture!))
        mesh.cullMode = .none
        mesh.label = "Knot"
        mesh.scale = .init(repeating: 2.5)
        scene.add(mesh)
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
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
