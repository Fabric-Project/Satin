//
//  MultipleViewportRenderer.swift
//  Example
//
//  Created by Reza Ali on 2/4/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Foundation

import Metal
import MetalKit
import Satin

final class MultipleViewportRenderer: BaseRenderer {
    final class ViewportMaterial: SourceMaterial {}
    final class AmplificationMaterial: SourceMaterial {}

    override var depthPixelFormat: MTLPixelFormat { .invalid }

    lazy var material = ViewportMaterial(pipelinesURL: pipelinesURL)
    lazy var mesh = Mesh(geometry: QuadGeometry(size: 2.0), material: material)
    lazy var startTime = getTime()
    lazy var renderer = Renderer(context: defaultContext)

    var camera = OrthographicCamera()

    lazy var subContext = Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat, depthPixelFormat: .depth32Float, vertexAmplificationCount: 2)
    lazy var subMesh = Mesh(geometry: IcosahedronGeometry(size: 0.5), material: BasicDiffuseMaterial(hardness: 1.0))
//    lazy var subMesh = Mesh(geometry: IcosahedronGeometry(size: 0.5), material: AmplificationMaterial(pipelinesURL: pipelinesURL))
    lazy var subScene = Object(label: "Subscene", [grid, axisMesh, subMesh])
    lazy var subRenderer = Renderer(context: subContext)

    var _updateTextures = true
    var subColorTexture: MTLTexture?
    var subDepthTexture: MTLTexture?
    var subRenderPassDescriptor = MTLRenderPassDescriptor()

    lazy var subCamera0 = PerspectiveCamera(position: [0, 4, 4], near: 0.01, far: 100.0, fov: 30)
    lazy var subCamera1 = PerspectiveCamera(position: [4, 4, 4], near: 0.01, far: 100.0, fov: 30)
    var subViewport = MTLViewport()

    lazy var grid: Object = {
        let object = Object()
        let material = BasicColorMaterial(color: simd_make_float4(1.0, 1.0, 1.0, 1.0))
        let intervals = 5
        let intervalsf = Float(intervals)
        let geometryX = CapsuleGeometry(radius: 0.005, height: intervalsf, axis: .x)
        let geometryZ = CapsuleGeometry(radius: 0.005, height: intervalsf, axis: .z)
        for i in 0 ... intervals {
            let fi = Float(i)
            let meshX = Mesh(geometry: geometryX, material: material)
            let offset = remap(fi, 0.0, Float(intervals), -intervalsf * 0.5, intervalsf * 0.5)
            meshX.position = [0.0, 0.0, offset]
            object.add(meshX)

            let meshZ = Mesh(geometry: geometryZ, material: material)
            meshZ.position = [offset, 0.0, 0.0]
            object.add(meshZ)
        }
        return object
    }()

    lazy var axisMesh: Object = {
        let object = Object()
        let intervals = 5
        let intervalsf = Float(intervals)
        let radius = Float(0.005)
        let height = intervalsf
        object.add(Mesh(geometry: CapsuleGeometry(radius: radius, height: height, axis: .x), material: BasicColorMaterial(color: simd_make_float4(1.0, 0.0, 0.0, 1.0))))
        object.add(Mesh(geometry: CapsuleGeometry(radius: radius, height: height, axis: .y), material: BasicColorMaterial(color: simd_make_float4(0.0, 1.0, 0.0, 1.0))))
        object.add(Mesh(geometry: CapsuleGeometry(radius: radius, height: height, axis: .z), material: BasicColorMaterial(color: simd_make_float4(0.0, 0.0, 1.0, 1.0))))
        return object
    }()

    override func setup() {
        subCamera0.lookAt(target: .zero)
        subCamera0.update()

        subCamera1.lookAt(target: .zero)
        subCamera1.update()

#if os(visionOS)
        renderer.setClearColor(.zero)
        subRenderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        if _updateTextures {
            setupTextures()
        }

        subRenderer.draw(
            renderPassDescriptor: subRenderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: subScene,
            cameras: [subCamera0, subCamera1],
            viewports: [subViewport, subViewport]
        )

        material.set(subColorTexture, index: FragmentTextureIndex.Custom0)

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: mesh,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        _updateTextures = true
    }

    func setupTextures() {
        let halfWidth = renderer.size.width / 2
        let height = renderer.size.height

        subColorTexture = createTextureArray(
            label: "Color Texture",
            width: Int(halfWidth),
            height: Int(height),
            arrayLength: subContext.vertexAmplificationCount,
            pixelFormat: subContext.colorPixelFormat,
            device: device
        )

        subDepthTexture = createTextureArray(
            label: "Depth Texture",
            width: Int(halfWidth),
            height: Int(height),
            arrayLength: subContext.vertexAmplificationCount,
            pixelFormat: subContext.depthPixelFormat,
            device: device
        )

        subRenderPassDescriptor.colorAttachments[0].texture = subColorTexture
        subRenderPassDescriptor.depthAttachment.texture = subDepthTexture
        subRenderPassDescriptor.renderTargetArrayLength = subContext.vertexAmplificationCount

        subViewport = MTLViewport(originX: 0, originY: 0, width: Double(halfWidth), height: Double(height), znear: 0, zfar: 1)
        subRenderer.resize((halfWidth, height))
        subCamera0.aspect = halfWidth / height
        subCamera1.aspect = halfWidth / height

        _updateTextures = false
    }

    func updateTextures() {
        guard _updateTextures else { return }
        setupTextures()
    }

    func createTextureArray(label: String, width: Int, height: Int, arrayLength: Int, pixelFormat: MTLPixelFormat, device: MTLDevice) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.sampleCount = 1
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = arrayLength
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }
}
