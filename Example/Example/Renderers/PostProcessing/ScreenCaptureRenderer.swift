//
//  ScreenCaptureRenderer.swift
//  Example
//
//  Created by Reza Ali on 7/18/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

#if os(macOS)

import Combine
import CoreVideo
import Metal
import MetalKit
import Satin
import ScreenCaptureKit

struct CapturedFrame {
    static var invalid: CapturedFrame {
        CapturedFrame(surface: nil, contentRect: .zero, contentScale: 0, scaleFactor: 0)
    }

    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

final class ScreenCaptureManager: NSObject, SCStreamDelegate, SCStreamOutput {
    var stream: SCStream?

    let framePublisher = PassthroughSubject<CapturedFrame, Never>()

    override init() {
        super.init()
    }

    func setup() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )

            let excludedApps = content.applications.filter { app in
                Bundle.main.bundleIdentifier == app.bundleIdentifier
            }

            let display = content.displays.first!
            let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = false
            configuration.captureResolution = .best
            configuration.width = display.width
            configuration.height = display.height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.queueDepth = 3

            stream = SCStream(filter: filter, configuration: configuration, delegate: self)

            // Add a stream output to capture screen content.
            try stream?.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "ScreenCaptureQueue")
            )
        } catch {
            print("Stream Setup Error: \(error.localizedDescription)")
        }
    }

    func start() async {
        do {
            try await stream?.startCapture()
        } catch {
            print("Stream Start Error: \(error.localizedDescription)")
        }
    }

    func stop() async {
        do {
            try await stream?.stopCapture()
        } catch {
            print("Stream Stop Error: \(error.localizedDescription)")
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        // Return early if the sample buffer is invalid.
        guard sampleBuffer.isValid else { return }

        // Determine which type of data the sample buffer contains.
        switch outputType {
            case .screen:
                handleLatestScreenSample(sampleBuffer)
            case .audio:
                break
            case .microphone:
                break
            @unknown default:
                break
        }
    }

    func handleLatestScreenSample(_ sampleBuffer: CMSampleBuffer) {
        // Retrieve the array of metadata attachments from the sample buffer.
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                             createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first else { return }

        // Validate the status of the frame. If it isn't `.complete`, return nil.
        guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete else { return }

        // Get the pixel buffer that contains the image data.
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // Get the backing IOSurface.
        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)

        // Retrieve the content rectangle, scale, and scale factor.
        guard let contentRectDict = attachments[.contentRect],
              let contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
              let contentScale = attachments[.contentScale] as? CGFloat,

              let scaleFactor = attachments[.scaleFactor] as? CGFloat else { return }

        framePublisher.send(CapturedFrame(surface: surface,
                                          contentRect: contentRect,
                                          contentScale: contentScale,
                                          scaleFactor: scaleFactor))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("Steam Error: \(error.localizedDescription)")
    }
}

final class ScreenCaptureRenderer: BaseRenderer {
    let material = BasicTextureMaterial()
    lazy var mesh = Mesh(label: "Quad", geometry: QuadGeometry(), material: material)

    var camera = OrthographicCamera(left: -2, right: 2, bottom: -2, top: 2, near: 0.0, far: 1)
    lazy var cameraController = OrthographicCameraController(camera: camera, view: metalView, defaultZoom: 1.0)
    lazy var scene = Object(label: "Scene", [mesh])
    lazy var renderer = Renderer(context: defaultContext)

    let captureManager = ScreenCaptureManager()

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    var frameSubscription: AnyCancellable?

    var texture: MTLTexture?
    override func setup() {
#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif

        frameSubscription = captureManager.framePublisher.sink { [weak self] frame in
            guard let self, let surface = frame.surface else { return }

            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: self.colorPixelFormat,
                width: surface.width,
                height: surface.height,
                mipmapped: false
            )

            if surface.pixelFormat == kCVPixelFormatType_32RGBA {
                print("found right format")
            }

            self.texture = self.device.makeTexture(
                descriptor: desc,
                iosurface: surface,
                plane: 0
            )
        }

        Task {
            await captureManager.setup()
            print("Setup Screen Capture")
            await captureManager.start()
            print("Starting Screen Capture")
        }
    }

    override func update() {
        cameraController.update()

        if let texture {
            material.flipped = false
            material.texture = texture
            mesh.scale = simd_make_float3(Float(texture.width), Float(texture.height), 1.0)
        } else {
            material.texture = nil
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
        cameraController.resize(size)
        renderer.resize(size)
    }

    override func cleanup() {
        Task {
            await captureManager.stop()
            print("Stopped Screen Capture")
        }
        super.cleanup()
    }
}

#endif
