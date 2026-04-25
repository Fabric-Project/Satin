//
//  MetalLayerRenderer.swift
//
//
//  Created by Reza Ali on 1/23/24.
//

#if os(visionOS)

import CompositorServices
import Metal
import simd
import Spatial
import SwiftUI

extension LayerRenderer.Clock.Instant.Duration {
    var timeInterval: TimeInterval {
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
    }
}

open class MetalLayerRenderer: CompositorLayerConfiguration {
    open var id: String {
        var result = String(describing: type(of: self)).replacingOccurrences(of: "Renderer", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != result {
            result = result.replacingOccurrences(of: bundleName, with: "")
        }
        result = result.replacingOccurrences(of: ".", with: "")
        return result
    }

    public internal(set) var layerRenderer: LayerRenderer!
    public internal(set) var arSession = ARKitSession()
    public internal(set) var worldTracking = WorldTrackingProvider()

    public internal(set) var isSetup: Bool = false

    public internal(set) var device: MTLDevice!
    public internal(set) var commandQueue: MTLCommandQueue!

    open var arSessionDataProviders: [any DataProvider] {
        [
            worldTracking
        ]
    }

    open var sampleCount: Int { 1 }
    open var colorPixelFormat: MTLPixelFormat { .bgra8Unorm_srgb }
    open var colorTextureUsage: MTLTextureUsage { [.renderTarget, .shaderRead] }

    open var depthPixelFormat: MTLPixelFormat { .depth32Float }
    open var depthTextureUsage: MTLTextureUsage { [.renderTarget, .shaderRead] }

    open var isFoveationEnabled: Bool { true }

#if targetEnvironment(simulator)
    open var layerLayout: LayerRenderer.Layout { .dedicated }
#else
    open var layerLayout: LayerRenderer.Layout { .layered }
#endif

    public var frameIndex: Int = -1

    public var defaultContext: Context {
        Context(
            device: device,
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            vertexAmplificationCount: layerRenderer.configuration.layout == .layered ? 2 : 1
        )
    }

    private let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    var onDisappearAction: (() -> Void)?

    public init() {}

    public func onDisappear(perform action: @escaping () -> Void) -> Self {
        onDisappearAction = action
        return self
    }

    public func startARSession() {
        Task {
            do {
                try await arSession.run(arSessionDataProviders)
            } catch {
                fatalError("Failed to initialize ARSession")
            }
        }
    }

    public func startRenderLoop() {
        Task {
            let renderThread = Thread {
                self.renderLoop()
            }
            renderThread.name = "\(id) Render Thread"
            renderThread.start()
        }
    }

    func renderLoop() {
        while true {
            if layerRenderer.state == .invalidated {
                cleanup()
                onDisappearAction?()
                return
            } else if layerRenderer.state == .paused {
                layerRenderer.waitUntilRunning()
                continue
            } else {
                autoreleasepool {
                    self.renderFrame()
                }
            }
        }
    }

    open func makeConfiguration(capabilities: LayerRenderer.Capabilities, configuration: inout LayerRenderer.Configuration) {
        configuration.colorFormat = colorPixelFormat
        configuration.colorUsage = colorTextureUsage

        configuration.depthFormat = depthPixelFormat
        configuration.depthUsage = depthTextureUsage

        let foveationEnabled = isFoveationEnabled && capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveationEnabled

        let options: LayerRenderer.Capabilities.SupportedLayoutsOptions = foveationEnabled ? [.foveationEnabled] : []
        let supportedLayouts = capabilities.supportedLayouts(options: options)
        configuration.layout = supportedLayouts.contains(layerLayout) ? layerLayout : .dedicated
    }

    open func setup() {}

    open func update() {}

    open func cleanup() {}

    open func drawView(
        view: Int,
        frame: LayerRenderer.Frame,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        camera: PerspectiveCamera,
        viewport: MTLViewport
    ) {}

    open func draw(
        frame: LayerRenderer.Frame,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        cameras: [PerspectiveCamera],
        viewports: [MTLViewport],
        viewMappings: [MTLVertexAmplificationViewMapping]
    ) {}

    open func preDraw(frame: LayerRenderer.Frame) -> (drawable: LayerRenderer.Drawable, commandBuffer: MTLCommandBuffer, cameras: [PerspectiveCamera])? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to create command buffer")
        }

        guard let drawable = frame.queryDrawable() else { return nil }

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        frameIndex += 1

        frame.startSubmission()

        let time = LayerRenderer.Clock.Instant.epoch.duration(to: drawable.frameTiming.presentationTime).timeInterval

        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)

        drawable.deviceAnchor = deviceAnchor

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        return (
            drawable: drawable,
            commandBuffer: commandBuffer,
            cameras: updateCameras(
                drawable: drawable,
                deviceAnchor: deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4
            )
        )
    }

    open func draw(
        frame: LayerRenderer.Frame,
        drawable: LayerRenderer.Drawable,
        commandBuffer: MTLCommandBuffer,
        cameras: [PerspectiveCamera]
    ) {
        if layerRenderer.configuration.layout == .dedicated {
            let indexOffset = (frameIndex % maxBuffersInFlight) * 2 // 0 1 2
            for i in 0 ..< drawable.views.count {
                let renderPassDescriptor = MTLRenderPassDescriptor()
                if sampleCount > 1 {
                    renderPassDescriptor.colorAttachments[0].texture = getMultisampleColorTexture(
                        ref: drawable.colorTextures[i],
                        index: i + indexOffset
                    )
                    renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.colorTextures[i]

                    renderPassDescriptor.depthAttachment.texture = getMultisampleDepthTexture(
                        ref: drawable.depthTextures[i],
                        index: i + indexOffset
                    )
                    renderPassDescriptor.depthAttachment.resolveTexture = drawable.depthTextures[i]
                } else {
                    renderPassDescriptor.colorAttachments[0].texture = drawable.colorTextures[i]
                    renderPassDescriptor.depthAttachment.texture = drawable.depthTextures[i]
                }

                if layerRenderer.configuration.isFoveationEnabled {
#if targetEnvironment(simulator)
                    renderPassDescriptor.rasterizationRateMap = drawable.rasterizationRateMaps.first
#else
                    renderPassDescriptor.rasterizationRateMap = drawable.rasterizationRateMaps[i]
#endif
                }

                drawView(
                    view: i,
                    frame: frame,
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    camera: cameras[i],
                    viewport: drawable.views[i].textureMap.viewport
                )
            }
        } else {
            let renderPassDescriptor = MTLRenderPassDescriptor()

            if sampleCount > 1 {
                let indexOffset = frameIndex % maxBuffersInFlight
                renderPassDescriptor.colorAttachments[0].texture = getMultisampleColorTexture(
                    ref: drawable.colorTextures[0],
                    index: indexOffset
                )
                renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.colorTextures[0]

                renderPassDescriptor.depthAttachment.texture = getMultisampleDepthTexture(
                    ref: drawable.depthTextures[0],
                    index: indexOffset
                )
                renderPassDescriptor.depthAttachment.resolveTexture = drawable.depthTextures[0]
            } else {
                renderPassDescriptor.colorAttachments[0].texture = drawable.colorTextures[0]
                renderPassDescriptor.depthAttachment.texture = drawable.depthTextures[0]
            }

            renderPassDescriptor.rasterizationRateMap = drawable.rasterizationRateMaps.first
            renderPassDescriptor.renderTargetArrayLength = drawable.views.count

            var viewports = [MTLViewport]()
            var viewMappings = [MTLVertexAmplificationViewMapping]()

            for (index, view) in drawable.views.enumerated() {
                viewports.append(view.textureMap.viewport)
                viewMappings.append(
                    MTLVertexAmplificationViewMapping(
                        viewportArrayIndexOffset: UInt32(index),
                        renderTargetArrayIndexOffset: UInt32(view.textureMap.sliceIndex)
                    )
                )
            }

            draw(
                frame: frame,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                cameras: cameras,
                viewports: viewports,
                viewMappings: viewMappings
            )
        }
    }

    open func postDraw(frame: LayerRenderer.Frame, drawable: LayerRenderer.Drawable, commandBuffer: MTLCommandBuffer) {
        drawable.encodePresent(commandBuffer: commandBuffer)

        commandBuffer.commit()

        frame.endSubmission()
    }

    open func renderFrame() {
        guard let frame = layerRenderer.queryNextFrame() else { return }

        frame.startUpdate()

        update()

        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }

        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        guard let (drawable, commandBuffer, cameras) = preDraw(frame: frame) else { return }

        draw(frame: frame, drawable: drawable, commandBuffer: commandBuffer, cameras: cameras)

        postDraw(frame: frame, drawable: drawable, commandBuffer: commandBuffer)
    }

    var colorMultisampleTextures: [MTLTexture?] = []

    func getMultisampleColorTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        var replace = false

        if colorMultisampleTextures.count > index,
           let colorMultisampleTexture = colorMultisampleTextures[index]
        {
            if colorMultisampleTexture.width == ref.width && colorMultisampleTexture.height == ref.height {
                return colorMultisampleTexture
            } else {
                replace = true
            }
        }

        let dedicated = layerRenderer.configuration.layout == .dedicated
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = colorPixelFormat
        descriptor.width = ref.width
        descriptor.height = ref.height
        descriptor.sampleCount = sampleCount
        descriptor.textureType = dedicated ? .type2DMultisample : .type2DMultisampleArray
        descriptor.arrayLength = dedicated ? 1 : 2
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .memoryless
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)

        if layerLayout == .dedicated {
            texture?.label = "\(id) Multisample Color Texture \(index % 2 == 1 ? "Right" : "Left") \(index / 2)/\(maxBuffersInFlight)"
        } else {
            texture?.label = "\(id) Multisample Color Texture \(index + 1)/\(maxBuffersInFlight)"
        }

        if replace {
            colorMultisampleTextures[index] = texture
        } else {
            colorMultisampleTextures.append(texture)
        }

        return texture
    }

    var depthMultisampleTextures: [MTLTexture?] = []

    func getMultisampleDepthTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        var replace = false

        if depthMultisampleTextures.count > index,
           let depthMultisampleTexture = depthMultisampleTextures[index]
        {
            if depthMultisampleTexture.width == ref.width && depthMultisampleTexture.height == ref.height {
                return depthMultisampleTexture
            } else {
                replace = true
            }
        }

        let dedicated = layerRenderer.configuration.layout == .dedicated
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = depthPixelFormat
        descriptor.width = ref.width
        descriptor.height = ref.height
        descriptor.sampleCount = sampleCount
        descriptor.textureType = dedicated ? .type2DMultisample : .type2DMultisampleArray
        descriptor.arrayLength = dedicated ? 1 : 2
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .memoryless
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)

        if layerLayout == .dedicated {
            texture?.label = "\(id) Multisample Depth Texture \(index % 2 == 1 ? "Right" : "Left") \(index / 2)/\(maxBuffersInFlight)"
        } else {
            texture?.label = "\(id) Multisample Depth Texture \(index + 1)/\(maxBuffersInFlight)"
        }

        if replace {
            depthMultisampleTextures[index] = texture
        } else {
            depthMultisampleTextures.append(texture)
        }

        return texture
    }
}

fileprivate func updateCameras(drawable: LayerRenderer.Drawable, deviceAnchor: simd_float4x4) -> [PerspectiveCamera] {
    var cameras = [PerspectiveCamera]()

    for i in 0 ..< drawable.views.count {
        let info = getCameraInfo(
            drawable: drawable,
            deviceAnchor: deviceAnchor,
            forViewIndex: i
        )

        let camera = PerspectiveCamera()

        camera.viewMatrix = info.view
        camera.updateViewMatrix = false

        camera.projectionMatrix = info.projection
        camera.updateProjectionMatrix = false

        cameras.append(camera)
    }

    return cameras
}

fileprivate func getCameraInfo(drawable: LayerRenderer.Drawable, deviceAnchor: simd_float4x4, forViewIndex viewIndex: Int) -> (view: simd_float4x4, projection: simd_float4x4) {
    let view = drawable.views[viewIndex]

    return (
        (deviceAnchor * view.transform).inverse,
        .init(ProjectiveTransform3D(
            leftTangent: Double(view.tangents[0]),
            rightTangent: Double(view.tangents[1]),
            topTangent: Double(view.tangents[2]),
            bottomTangent: Double(view.tangents[3]),
            nearZ: Double(drawable.depthRange.y),
            farZ: Double(drawable.depthRange.x),
            reverseZ: true
        ))
    )
}

#endif
