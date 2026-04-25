//
//  ARMatteRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/11/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Foundation
import Metal

public class ARMatteRenderer {
    private var device: MTLDevice
    private var matteGenerator: ARMatteGenerator
    private var viewportSize = CGSize(width: 0, height: 0)
    private var _updateGeometry = true
    private var _updateTextures = true
    private var renderer: Renderer

    var material = ARMatteMaterial()
    private var mesh = Mesh(geometry: QuadGeometry(), material: nil)
    private var camera = OrthographicCamera()

    public internal(set) var alphaTexture: MTLTexture?
    public internal(set) var dilatedDepthTexture: MTLTexture?

    unowned var session: ARSession

    public init(device: MTLDevice, session: ARSession, matteResolution: ARMatteGenerator.Resolution, near: Float, far: Float) {
        self.device = device
        self.session = session
        self.matteGenerator = ARMatteGenerator(device: device, matteResolution: matteResolution)
        self.renderer = Renderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .r32Float, depthPixelFormat: .depth32Float))
        renderer.setClearColor(.zero)
        renderer.label = "AR Matte Renderer"

        mesh.material = material
        material.set("Near Far Delta", [near, far, far - near])

        NotificationCenter.default.addObserver(self, selector: #selector(ARMatteRenderer.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc func rotated() {
        _updateGeometry = true
    }

    public func encode(commandBuffer: MTLCommandBuffer) {
        guard let frame = session.currentFrame else { return }

        material.alphaTexture = matteGenerator.generateMatte(from: frame, commandBuffer: commandBuffer)
        material.dilatedDepthTexture = matteGenerator.generateDilatedDepth(from: frame, commandBuffer: commandBuffer)

        if _updateGeometry {
            updateGeometry(frame)
            _updateGeometry = false
        }

        if _updateTextures {
            updateTextures()
            _updateTextures = false
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = alphaTexture
        rpd.depthAttachment.texture = dilatedDepthTexture

        renderer.draw(
            renderPassDescriptor: rpd,
            commandBuffer: commandBuffer,
            scene: mesh,
            camera: camera
        )
    }

    private func updateGeometry(_ frame: ARFrame) {
        guard let interfaceOrientation = UIWindow.keyWindow?.windowScene?.interfaceOrientation else { return }

        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize).inverted()

        let geo = QuadGeometry()
        let vertexCount = Int(geo.geometryData.vertexCount)
        for i in 0 ..< vertexCount {
            let vertex = geo.geometryData.vertexData[i]
            let uv = vertex.uv
            let textureCoord = CGPoint(x: CGFloat(uv.x), y: CGFloat(uv.y))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            geo.geometryData.vertexData[i].uv = simd_make_float2(Float(transformedCoord.x), Float(transformedCoord.y))
        }
        mesh.geometry = geo
    }

    private func updateTextures() {
        alphaTexture = createTexture("Matte Alpha Texture", renderer.context.colorPixelFormat)
        dilatedDepthTexture = createTexture("Matte Depth Texture", renderer.context.depthPixelFormat)
    }

    public func resize(_ size: (width: Float, height: Float)) {
        _updateGeometry = true
        _updateTextures = true
        viewportSize = CGSize(width: Int(size.width), height: Int(size.height))
        renderer.resize(size)
    }

    private func createTexture(_ label: String, _ pixelFormat: MTLPixelFormat) -> MTLTexture? {
        if viewportSize.width > 0, viewportSize.height > 0 {
            let descriptor = MTLTextureDescriptor()
            descriptor.pixelFormat = pixelFormat
            descriptor.width = Int(viewportSize.width)
            descriptor.height = Int(viewportSize.height)
            descriptor.sampleCount = 1
            descriptor.textureType = .type2D
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            descriptor.resourceOptions = .storageModePrivate
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            texture.label = label
            return texture
        }
        return nil
    }
}

#endif
