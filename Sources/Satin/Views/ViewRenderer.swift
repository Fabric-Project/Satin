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

    public internal(set) var appearance: Appearance = .unspecified {
        didSet {
            updateAppearance()
        }
    }

    open func updateAppearance() {}

    open override func cleanup() {
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

    func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable) {
        guard isSetup, let commandBuffer = preDraw() else { return }

        update()
        draw(texture: drawable.texture, commandBuffer: commandBuffer)
        postDraw(drawable: drawable, commandBuffer: commandBuffer)
    }

    func drawableResized(size: CGSize, scaleFactor: CGFloat) {
#if DEBUG_VIEWS
        print("renderer resize: \(size), scaleFactor: \(scaleFactor) - ViewRenderer: \(id)")
#endif
        resize(size: (Float(size.width), Float(size.height)), scaleFactor: Float(scaleFactor))
    }
}
