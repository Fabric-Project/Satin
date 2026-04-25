//
//  BloomRenderer.swift
//  Example
//
//  Created by Reza Ali on 9/2/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Metal
import Satin
import simd

final class BloomRenderer: BaseRenderer {
    override var paramKeys: [String] {
        return [
            "Post Material",
        ]
    }

    override var params: [String: ParameterGroup?] {
        return [
            "Post Material": postMaterial.parameters,
        ]
    }

    override var colorPixelFormat: MTLPixelFormat { .rgba16Float }

    var size = simd_int2(repeating: 0)

    final class PostMaterial: SourceMaterial {}

    var renderTexture: MTLTexture?

    lazy var scene: Object = {
        let scene = Object(label: "Scene")
        let mesh = InstancedMesh(geometry: IcoSphereGeometry(radius: 1.0, resolution: 4), material: StandardMaterial(baseColor: [0.25, 0.25, 0.25, 1], metallic: 1, roughness: 0.2, specular: 1.0), count: 10)
        for index in 0 ..< 10 {
            let scale = Float.random(in: 0.1 ... 0.5)
            let magnitude = (1.0 - scale) * 10.0
            let object = Object()
            object.scale = simd_float3(repeating: scale)
            object.position = [Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude)]
            object.orientation = simd_quatf(angle: Float.random(in: -Float.pi ... Float.pi), axis: simd_normalize(object.position))

            mesh.setMatrixAt(index: index, matrix: object.worldMatrix)
        }
        scene.add(mesh)

        let directionlLight = DirectionalLight(color: [1, 1, 1], intensity: 2.0)
        directionlLight.position = [10, 10, 10]
        directionlLight.lookAt(target: .zero)
        scene.add(directionlLight)

        let directionlLight2 = DirectionalLight(color: [1, 1, 1], intensity: 2.0)
        directionlLight2.position = [-10, 10, 10]
        directionlLight2.lookAt(target: .zero)
        scene.add(directionlLight2)

        let directionlLight3 = DirectionalLight(color: [1, 1, 1], intensity: 2.0)
        directionlLight3.position = [10, -10, -10]
        directionlLight3.lookAt(target: .zero)
        scene.add(directionlLight3)

        let boxMesh = InstancedMesh(geometry: RoundedBoxGeometry(size: 1.0, radius: 0.25, resolution: 3), material: StandardMaterial(baseColor: [0.5, 0.5, 0.5, 1], metallic: 1.0, roughness: 0.1), count: 20)
        for index in 0 ..< 20 {
            let scale = Float.random(in: 0.1 ... 0.75)
            let magnitude = (1.0 - scale) * 10.0
            let object = Object()
            object.scale = simd_float3(repeating: scale)
            object.position = [Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude)]
            object.orientation = simd_quatf(angle: Float.random(in: -Float.pi ... Float.pi), axis: simd_normalize(object.position))

            boxMesh.setMatrixAt(index: index, matrix: object.worldMatrix)
        }
        scene.add(boxMesh)

        let capusleMesh = InstancedMesh(geometry: CapsuleGeometry(radius: 0.5, height: 2.0), material: StandardMaterial(baseColor: [0.93, 0.36, 0.46, 1], metallic: 1.0, roughness: 0.0), count: 20)
        for index in 0 ..< 20 {
            let scale = Float.random(in: 0.1 ... 0.75)
            let magnitude = (1.0 - scale) * 10.0
            let object = Object()
            object.scale = simd_float3(repeating: scale)
            object.position = [Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude)]
            object.orientation = simd_quatf(angle: Float.random(in: -Float.pi ... Float.pi), axis: simd_normalize(object.position))

            capusleMesh.setMatrixAt(index: index, matrix: object.worldMatrix)
        }
        scene.add(capusleMesh)

        return scene
    }()

    lazy var postMaterial = PostMaterial(pipelinesURL: pipelinesURL, live: true)
    lazy var postProcessor = PostProcessor(
        label: "Bloom Post Processor",
        context: Context(
            device: device,
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat
        ),
        material: postMaterial
    )

    var camera = PerspectiveCamera(position: [0.0, 0.0, 10.0], near: 0.001, far: 100.0, fov: 45.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    lazy var bloomGenerator = BloomGenerator(device: device, levels: 5)

    deinit {
        cameraController.disable()
    }

    override func update() {
        if size.x != Int(metalView.drawableSize.width) || size.y != Int(metalView.drawableSize.height) {
            renderTexture = createTexture(
                "Render Texture",
                Int(metalView.drawableSize.width),
                Int(metalView.drawableSize.height),
                colorPixelFormat,
                device
            )
            size = simd_make_int2(Int32(Int(metalView.drawableSize.width)), Int32(metalView.drawableSize.height))
        }

        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard let renderTexture else { return }
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            renderTarget: renderTexture
        )

        let bloomTexture = bloomGenerator.encode(commandBuffer: commandBuffer, sourceTexture: renderTexture)
        postProcessor.mesh.material?.set(renderTexture, index: FragmentTextureIndex.Custom0)
        postProcessor.mesh.material?.set(bloomTexture, index: FragmentTextureIndex.Custom1)

        postProcessor.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
        postProcessor.resize(size: size, scaleFactor: scaleFactor)
    }

    func createTexture(_ label: String, _ width: Int, _ height: Int, _ pixelFormat: MTLPixelFormat, _ device: MTLDevice) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }
}
