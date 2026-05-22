//
//  ARBackgroundEncoder.swift
//  Example
//
//  Created by Reza Ali on 3/15/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Foundation
import Metal

public class ARBackgroundEncoder: PostProcessEncoder {
    // Captured image texture cache
    private var capturedImageTextureCache: CVMetalTextureCache!
    var viewportSize = CGSize(width: 0, height: 0)
    private var _updateGeometry = true

    public private(set) var capturedImageTextureY: CVMetalTexture? {
        didSet {
            backgroundMaterial.capturedImageTextureY = capturedImageTextureY
        }
    }

    public private(set) var capturedImageTextureCbCr: CVMetalTexture? {
        didSet {
            backgroundMaterial.capturedImageTextureCbCr = capturedImageTextureCbCr
        }
    }

    unowned var session: ARSession

    private var backgroundMaterial: ARBackgroundMaterial

    public var colorTexture: MTLTexture? {
        renderer.colorTexture
    }

    public init(context: Context, session: ARSession) {
        self.session = session

        backgroundMaterial = ARBackgroundMaterial(context:context, srgb: false)

        super.init(label: "AR Background RenderEncoder", context: context, material: backgroundMaterial)

        renderer.setClearColor(.zero)
        renderer.frameBufferOnly = false
        setupTextureCache()

        NotificationCenter.default.addObserver(self, selector: #selector(ARBackgroundEncoder.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)

        mesh.label = "AR Background Color Mesh"
        mesh.visible = false

        mesh.onUpdate = { [weak self] in
            guard let self, let frame = self.session.currentFrame else { return }

            self.updateTextures(frame)

            if self._updateGeometry {
                self.updateGeometry(frame)
                self._updateGeometry = false
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc func rotated() {
        _updateGeometry = true
    }

    override public func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        super.resize(size: size, scaleFactor: scaleFactor)
        _updateGeometry = true
        viewportSize = CGSize(width: Int(size.width), height: Int(size.height))
    }

    // MARK: - Internal Methods

    func updateGeometry(_ frame: ARFrame) {
        guard let interfaceOrientation = getOrientation() else { return }

        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize).inverted()

        guard let geo = mesh.geometry as? QuadGeometry else { return }
        let vertexCount = Int(geo.geometryData.vertexCount)
        for i in 0 ..< vertexCount {
            let vertex = geo.geometryData.vertexData[i]
            let uv = vertex.uv
            let textureCoord = CGPoint(x: CGFloat(uv.x), y: CGFloat(uv.y))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            geo.geometryData.vertexData[i].uv = simd_make_float2(Float(transformedCoord.x), Float(transformedCoord.y))
        }
        geo.setFrom(geometryData: geo.geometryData)
    }

    func updateTextures(_ frame: ARFrame) {
        if CVPixelBufferGetPlaneCount(frame.capturedImage) == 2 {
            capturedImageTextureY = createTexture(
                fromPixelBuffer: frame.capturedImage,
                pixelFormat: .r8Unorm,
                planeIndex: 0
            )

            capturedImageTextureCbCr = createTexture(
                fromPixelBuffer: frame.capturedImage,
                pixelFormat: .rg8Unorm,
                planeIndex: 1
            )

            mesh.visible = true
        } else {
            mesh.visible = false
        }
    }

    func setupTextureCache() {
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, context.device, nil, &textureCache)
        capturedImageTextureCache = textureCache
    }

    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)

        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)

        if status != kCVReturnSuccess {
            texture = nil
        }

        return texture
    }

    func getOrientation() -> UIInterfaceOrientation? {
        return UIWindow.keyWindow?.windowScene?.interfaceOrientation
    }
}

#endif
