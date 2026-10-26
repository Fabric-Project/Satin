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

open class ViewRenderer: Renderer, ViewRendererDelegate {
    public enum Appearance {
        case unspecified
        case dark
        case light
    }

    public internal(set) unowned var metalView: MetalView!
    /// Whether a frame handed to `renderQueue` is still running; ticks meanwhile are skipped, so
    /// frames never queue up behind a slow one.
    private let pendingFrameLock = UnfairLock()
    private var isFramePending = false
    /// Under `pendingFrameLock`: the view's latest scale factor.
    private var latestScaleFactor: Float = 1
    /// `renderQueue` only: the drawable size the last resize was for.
    private var drawnSize: (Float, Float)?
    public weak var errorDelegate: ErrorRenderDelegate?

    public internal(set) var appearance: Appearance = .unspecified {
        didSet {
            updateAppearance()
        }
    }

    // A new setup needs its initial resize even if the drawable dimensions have not changed.
    // Observe the lifecycle state rather than requiring every setup/cleanup override to call super.
    override public internal(set) var isSetup: Bool {
        didSet { drawnSize = nil }
    }

    open func updateAppearance() {}

    open override func cleanup() throws {
#if DEBUG_VIEW
        print("\ncleanup - ViewRenderer: \(id)\n")
#endif
    }

    open func postDraw(drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
        commandBuffer.present(drawable)
        postDraw(commandBuffer: commandBuffer)
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

    // MARK: - ViewRendererDelegate

    var ticksOffMainThread: Bool { renderQueue != nil }

    /// A display tick: draws now, or on `renderQueue` unless the frame before is still running there.
    func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable, hostTime: TimeInterval, presentationHostTime: TimeInterval?) {
        guard let renderQueue else {
            drawFrame(drawable: drawable, hostTime: hostTime, presentationHostTime: presentationHostTime)
            return
        }
        let isFree = pendingFrameLock.sync {
            guard !isFramePending else { return false }
            isFramePending = true
            return true
        }
        guard isFree else { return }
        renderQueue.async {
            self.drawFrame(drawable: drawable, hostTime: hostTime, presentationHostTime: presentationHostTime)
            self.pendingFrameLock.sync { self.isFramePending = false }
        }
    }

    private func drawFrame(drawable: CAMetalDrawable, hostTime: TimeInterval, presentationHostTime: TimeInterval?) {
        guard isSetup else { return }
        if renderQueue != nil { resizeIfNeeded(for: drawable.texture) }
        guard let commandBuffer = preDraw() else { return }

        let frame = nextFrameTime(hostTime: hostTime, presentationHostTime: presentationHostTime)

        do {
            try update(frame: frame)
            try draw(texture: drawable.texture, commandBuffer: commandBuffer)
            postDraw(drawable: drawable, commandBuffer: commandBuffer)
        } catch {
            postDraw(commandBuffer: commandBuffer)
            errorDelegate?.renderer(self, didFailWith: error)
        }
    }

    func drawableResized(size: CGSize, scaleFactor: CGFloat) {
#if DEBUG_VIEWS
        print("renderer resize: \(size), scaleFactor: \(scaleFactor) - ViewRenderer: \(id)")
#endif
        guard renderQueue != nil else {
            resize(size: (Float(size.width), Float(size.height)), scaleFactor: Float(scaleFactor))
            return
        }
        // The size arrives with the next frame's drawable; only the scale has to be passed on.
        pendingFrameLock.sync { latestScaleFactor = Float(scaleFactor) }
    }

    /// With a `renderQueue`, the size a frame's drawable has is the size it draws at: resizing
    /// here, before update, means no frame can reach a new-size drawable before its resize.
    func resizeIfNeeded(for texture: MTLTexture) {
        let size = (Float(texture.width), Float(texture.height))
        if let drawnSize, drawnSize == size { return }
        drawnSize = size
        let scaleFactor = pendingFrameLock.sync { latestScaleFactor }
        resize(size: size, scaleFactor: scaleFactor)
    }
}
