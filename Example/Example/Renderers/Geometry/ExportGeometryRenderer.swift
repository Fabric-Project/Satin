//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 10/2/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import ModelIO

import Satin

final class ExportGeometryRenderer: BaseRenderer {
    lazy var material = BasicDiffuseMaterial(hardness: 0.9)

    lazy var metal: Mesh = {
        let geo = ExtrudedTextGeometry(text: "SATIN", fontName: "Ariel", fontSize: 1, distance: 0.5)
        let mesh = Mesh(label: "SATIN", geometry: geo, material: material)
        mesh.position = [0, 0.25, 0]
        return mesh
    }()

    lazy var rocks: Mesh = {
        let mesh = Mesh(label: "PRO", geometry: ExtrudedTextGeometry(text: "PRO", fontName: "Ariel", fontSize: 1, distance: 0.5),
                        material: material)
        mesh.position = [0, -0.75, 0]
        return mesh
    }()

    lazy var scene: Object = {
        let scene = Object()
        scene.add(metal)
        scene.add(rocks)
        scene.localMatrix = lookAtMatrix3f([0, 0, -1], [0, 1, 1], worldUpDirection)
        return scene
    }()

    var camera = PerspectiveCamera(position: [0, 0, 5], near: 0.001, far: 100.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    deinit {
        cameraController.disable()
    }

    override func setup() {
        #if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
        #endif
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

    func exportObj(_ url: URL) {
        let allocator = MDLMeshBufferDataAllocator()
        let asset = MDLAsset(bufferAllocator: allocator)

        let mdlObject = MDLObject()
        mdlObject.name = scene.label
        mdlObject.transform = MDLTransform(matrix: scene.localMatrix)

        let meshes = getMeshes(scene, true, false)

        for mesh in meshes {
            print("exporting: \(mesh.label)")
            guard let geometry = mesh.geometry as? SatinGeometry else { continue }

            var geometryData = geometry.geometryData

            let vertexCount = Int(geometryData.vertexCount)
            let vertexStride = MemoryLayout<SatinVertex>.stride
            let byteCountVertices = vertexCount * vertexStride

            let indexCount = Int(geometryData.indexCount * 3)
            let bytesPerIndex = MemoryLayout<UInt32>.size
            let byteCountIndices = indexCount * bytesPerIndex

            var data = duplicateGeometryData(&geometryData)
            transformGeometryData(&data, mesh.localMatrix)

            let mdlVertexBuffer = allocator.newBuffer(
                with: Data(bytes: data.vertexData, count: byteCountVertices),
                type: .vertex
            )

            let mdlIndexBuffer = allocator.newBuffer(
                with: Data(bytes: data.indexData, count: byteCountIndices),
                type: .index
            )

            let submesh = MDLSubmesh(
                indexBuffer: mdlIndexBuffer,
                indexCount: indexCount,
                indexType: .uInt32,
                geometryType: .triangles,
                material: nil
            )

            let descriptor = ModelIOVertexDescriptor(geometry.vertexDescriptor)

            let mdlMesh = MDLMesh(
                vertexBuffer: mdlVertexBuffer,
                vertexCount: vertexCount,
                descriptor: descriptor,
                submeshes: [submesh]
            )

            mdlObject.addChild(mdlMesh)

            freeGeometryData(&data)
        }

        asset.add(mdlObject)

        if MDLAsset.canExportFileExtension("obj") {
            print("can export objs")
            do {
                try asset.export(to: url)
            } catch {
                print("Export Error: \(error.localizedDescription)")
            }
        } else {
            fatalError("Can't export OBJ")
        }
    }

    #if os(macOS)

    override func keyDown(with event: NSEvent) -> Bool {
        if event.characters == "s" {
            exportObj()
            return true
        }
        return false
    }

    func exportObj() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.showsTagField = false
        panel.nameFieldStringValue = "test.obj"
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.modalPanelWindow)))
        panel.begin { result in
            if result.rawValue == NSApplication.ModalResponse.OK.rawValue, let url = panel.url {
                self.exportObj(url)
            }
        }
    }

    #endif
}
