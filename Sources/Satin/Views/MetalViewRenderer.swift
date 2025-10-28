//
//  ForgeRenderer.swift
//  Forging
//
//  Created by Reza Ali on 1/21/24.
//

import Foundation
import QuartzCore

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

open class MetalViewRenderer: MetalViewRendererDelegate {
    public enum Appearance {
        case unspecified
        case dark
        case light
    }

    open var id: String {
        var result = String(describing: type(of: self)).replacingOccurrences(of: "Renderer", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != result {
            result = result.replacingOccurrences(of: bundleName, with: "")
        }
        result = result.replacingOccurrences(of: ".", with: "")
        return result
    }

    public internal(set) unowned var metalView: MetalView!

    public internal(set) var device: MTLDevice!
    public internal(set) var commandQueue: MTLCommandQueue!

    public internal(set) var colorMultisampleTextures: [MTLTexture?] = []

    public internal(set) var depthTextures: [MTLTexture?] = []
    public internal(set) var depthMultisampleTextures: [MTLTexture?] = []

    public internal(set) var stencilTextures: [MTLTexture?] = []
    public internal(set) var stencilMultisampleTextures: [MTLTexture?] = []

    public internal(set) var isSetup = false

    public internal(set) var appearance: Appearance = .unspecified {
        didSet {
            updateAppearance()
        }
    }

    open var sampleCount: Int { 1 }
    open var colorPixelFormat: MTLPixelFormat { .bgra8Unorm }
    open var depthPixelFormat: MTLPixelFormat { .depth32Float }
    open var stencilPixelFormat: MTLPixelFormat { .invalid }

    open var colorTextureStorageMode: MTLStorageMode { .memoryless }
    open var colorTextureUsage: MTLTextureUsage { .renderTarget }

    open var depthTextureStorageMode: MTLStorageMode { .memoryless }
    open var depthTextureUsage: MTLTextureUsage { .renderTarget }

    open var stencilTextureStorageMode: MTLStorageMode { .memoryless }
    open var stencilTextureUsage: MTLTextureUsage { .renderTarget }

    public var defaultContext: Context {
        Context(
            device: device,
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat
        )
    }

    private let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    private var inFlightSemaphoreWait = 0
    private var inFlightSemaphoreRelease = 0
    public var frameIndex: Int = -1

    public init() {}

    open func setup() {}

    open func update() {}

    open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {}

    open func updateAppearance() {}

    open func cleanup() {
#if DEBUG_VIEW
        print("\ncleanup - MetalViewRenderer: \(id)\n")
#endif
    }

    deinit {
#if DEBUG_VIEW
        print("\ndeinit - MetalViewRenderer: \(id)\n")
#endif
        let delta = inFlightSemaphoreWait + inFlightSemaphoreRelease
        for _ in 0 ..< delta {
            inFlightSemaphore.signal()
        }
    }

    open func resize(size: (width: Float, height: Float), scaleFactor: Float) {}

    open func preDraw() -> MTLCommandBuffer? {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        frameIndex += 1

        if let commandBuffer = commandQueue.makeCommandBuffer() {
            inFlightSemaphoreWait += 1
            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.inFlightSemaphore.signal()
                self?.inFlightSemaphoreRelease -= 1
            }
            return commandBuffer
        }
        return nil
    }

    open func postDraw(drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Events

#if os(macOS)

    open func touchesBegan(with event: NSEvent) {}

    open func touchesEnded(with event: NSEvent) {}

    open func touchesMoved(with event: NSEvent) {}

    open func touchesCancelled(with event: NSEvent) {}

    open func scrollWheel(with event: NSEvent) {}

    open func mouseMoved(with event: NSEvent) {}

    open func mouseDown(with event: NSEvent) {}

    open func mouseDragged(with event: NSEvent) {}

    open func mouseUp(with event: NSEvent) {}

    open func mouseEntered(with event: NSEvent) {}

    open func mouseExited(with event: NSEvent) {}

    open func rightMouseDown(with event: NSEvent) {}

    open func rightMouseDragged(with event: NSEvent) {}

    open func rightMouseUp(with event: NSEvent) {}

    open func otherMouseDown(with event: NSEvent) {}

    open func otherMouseDragged(with event: NSEvent) {}

    open func otherMouseUp(with event: NSEvent) {}

    open func performKeyEquivalent(with event: NSEvent) -> Bool { return false }

    open func keyDown(with event: NSEvent) -> Bool { return false }

    open func keyUp(with event: NSEvent) -> Bool { return false }

    open func flagsChanged(with event: NSEvent) -> Bool { return false }

    open func magnify(with event: NSEvent) {}

    open func rotate(with event: NSEvent) {}

    open func swipe(with event: NSEvent) {}

#elseif os(iOS) || os(tvOS) || os(visionOS)

    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}

    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}

    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}

    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}

#endif

    // MARK: - ForgeMetalViewRenderDelegate

    func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable) {
        guard isSetup, let commandBuffer = preDraw() else { return }

        update()

        let renderPassDescriptor = MTLRenderPassDescriptor()

        let index = frameIndex % maxBuffersInFlight
        if sampleCount > 1 {
            renderPassDescriptor.colorAttachments[0].texture = getMultisampleColorTexture(ref: drawable.texture, index: index)
            renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.texture
            renderPassDescriptor.renderTargetWidth = drawable.texture.width
            renderPassDescriptor.renderTargetHeight = drawable.texture.height
            renderPassDescriptor.depthAttachment.texture = getMultisampleDepthTexture(ref: drawable.texture, index: index)
            renderPassDescriptor.depthAttachment.resolveTexture = getDepthTexture(ref: drawable.texture, index: index)
            renderPassDescriptor.stencilAttachment.texture = getMultisampleStencilTexture(ref: drawable.texture, index: index)
            renderPassDescriptor.stencilAttachment.resolveTexture = getStencilTexture(ref: drawable.texture, index: index)

        }
        else {
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.renderTargetWidth = drawable.texture.width
            renderPassDescriptor.renderTargetHeight = drawable.texture.height
            renderPassDescriptor.depthAttachment.texture = getDepthTexture(ref: drawable.texture, index: index)
            renderPassDescriptor.stencilAttachment.texture = getStencilTexture(ref: drawable.texture, index: index)
        }

        
        renderPassDescriptor.stencilAttachment.storeAction = .store
        renderPassDescriptor.stencilAttachment.loadAction = .clear
        renderPassDescriptor.stencilAttachment.clearStencil = 0

        draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        postDraw(drawable: drawable, commandBuffer: commandBuffer)
    }

    func getDepthTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard depthPixelFormat != .invalid else { return nil }

        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if depthTextures.count > index,
           let depthTexture = depthTextures[index]
        {
            if depthTexture.width == ref.width && depthTexture.height == ref.height {
                return depthTexture
            }
            else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = depthPixelFormat
        descriptor.width = ref.width
        descriptor.height = ref.height

        descriptor.sampleCount = 1
        descriptor.textureType = .type2D

        descriptor.usage = depthTextureUsage
        descriptor.storageMode = depthTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Depth Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            depthTextures[index] = texture
        }
        else {
            depthTextures.append(texture)
        }

        return texture
    }

    func getMultisampleDepthTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard sampleCount > 1, depthPixelFormat != .invalid else { return nil }

        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if depthMultisampleTextures.count > index,
           let depthMultisampleTexture = depthMultisampleTextures[index]
        {
            if depthMultisampleTexture.width == ref.width && depthMultisampleTexture.height == ref.height {
                return depthMultisampleTexture
            }
            else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = depthPixelFormat
        descriptor.sampleCount = sampleCount
        descriptor.textureType = .type2DMultisample

        descriptor.width = ref.width
        descriptor.height = ref.height

        descriptor.usage = depthTextureUsage
        descriptor.storageMode = depthTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Multisample Depth Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            depthMultisampleTextures[index] = texture
        }
        else {
            depthMultisampleTextures.append(texture)
        }

        return texture
    }
    
    func getStencilTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard stencilPixelFormat != .invalid else { return nil }

        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if stencilTextures.count > index,
           let stencilTexture = stencilTextures[index]
        {
            if stencilTexture.width == ref.width && stencilTexture.height == ref.height {
                return stencilTexture
            }
            else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = stencilPixelFormat
        descriptor.width = ref.width
        descriptor.height = ref.height

        descriptor.sampleCount = 1
        descriptor.textureType = .type2D

        descriptor.usage = stencilTextureUsage
        descriptor.storageMode = stencilTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Stencil Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            stencilTextures[index] = texture
        }
        else {
            stencilTextures.append(texture)
        }

        return texture
    }

    func getMultisampleStencilTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard sampleCount > 1, stencilPixelFormat != .invalid else { return nil }

        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if stencilMultisampleTextures.count > index,
           let stencilMultisampleTexture = stencilMultisampleTextures[index]
        {
            if stencilMultisampleTexture.width == ref.width && stencilMultisampleTexture.height == ref.height {
                return stencilMultisampleTexture
            }
            else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = stencilPixelFormat
        descriptor.sampleCount = sampleCount
        descriptor.textureType = .type2DMultisample

        descriptor.width = ref.width
        descriptor.height = ref.height

        descriptor.usage = stencilTextureUsage
        descriptor.storageMode = stencilTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Multisample Stencil Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            stencilMultisampleTextures[index] = texture
        }
        else {
            stencilMultisampleTextures.append(texture)
        }

        return texture
    }
    
    func getMultisampleColorTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        var replace = false

        if colorMultisampleTextures.count > index,
           let colorMultisampleTexture = colorMultisampleTextures[index]
        {
            if colorMultisampleTexture.width == ref.width && colorMultisampleTexture.height == ref.height {
                return colorMultisampleTexture
            }
            else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = colorPixelFormat
        descriptor.sampleCount = sampleCount
        descriptor.textureType = .type2DMultisample

        descriptor.width = ref.width
        descriptor.height = ref.height

        descriptor.usage = colorTextureUsage
        descriptor.storageMode = colorTextureStorageMode
        descriptor.resourceOptions = .storageModePrivate

        descriptor.allowGPUOptimizedContents = true

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Multisample Color Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            colorMultisampleTextures[index] = texture
        }
        else {
            colorMultisampleTextures.append(texture)
        }

        return texture
    }

    func drawableResized(size: CGSize, scaleFactor: CGFloat) {
#if DEBUG_VIEWS
        print("renderer resize: \(size), scaleFactor: \(scaleFactor) - MetalViewRenderer: \(id)")
#endif
        resize(size: (Float(size.width), Float(size.height)), scaleFactor: Float(scaleFactor))
    }
}
