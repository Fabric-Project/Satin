//
//  ForgeMetalViewRendererDelegate.swift
//  Forging
//
//  Created by Reza Ali on 1/22/24.
//

import Foundation
import QuartzCore

#if canImport(AppKit)
import AppKit
#endif

public protocol MetalViewRendererDelegate: AnyObject {
//    var id: String { get }
//    func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable)
//    func drawableResized(size: CGSize, scaleFactor: CGFloat)
    
    var id: String { get }
    func setup()
    func update()
    func drawableResized(size: CGSize, scaleFactor: CGFloat)
    func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable)
    func cleanup()
    
    var metalView: MetalView! { get set }

    var device: MTLDevice! { get set }
    var commandQueue: MTLCommandQueue! { get set }

    var colorMultisampleTextures: [MTLTexture?] { get set }

    var depthTextures: [MTLTexture?] { get set }
    var depthMultisampleTextures: [MTLTexture?] { get set }

    var isSetup:Bool { get set }

    var appearance: MetalViewRenderer.Appearance { get set }

    var sampleCount: Int { get }
    var colorPixelFormat: MTLPixelFormat { get }
    var depthPixelFormat: MTLPixelFormat { get }
    var stencilPixelFormat: MTLPixelFormat { get }

    var colorTextureStorageMode: MTLStorageMode { get  }
    var colorTextureUsage: MTLTextureUsage { get }

    var depthTextureStorageMode: MTLStorageMode { get }
    var depthTextureUsage: MTLTextureUsage { get }

    var defaultContext: Context { get }
    
#if os(macOS)

    func touchesBegan(with event: NSEvent)

    func touchesEnded(with event: NSEvent)

    func touchesMoved(with event: NSEvent)

    func touchesCancelled(with event: NSEvent) 

    func scrollWheel(with event: NSEvent) 

    func mouseMoved(with event: NSEvent) 

    func mouseDown(with event: NSEvent) 

    func mouseDragged(with event: NSEvent) 

    func mouseUp(with event: NSEvent) 

    func mouseEntered(with event: NSEvent) 

    func mouseExited(with event: NSEvent) 

    func rightMouseDown(with event: NSEvent) 

    func rightMouseDragged(with event: NSEvent) 

    func rightMouseUp(with event: NSEvent) 

    func otherMouseDown(with event: NSEvent) 

    func otherMouseDragged(with event: NSEvent) 

    func otherMouseUp(with event: NSEvent) 

    func performKeyEquivalent(with event: NSEvent) -> Bool

    func keyDown(with event: NSEvent) -> Bool

    func keyUp(with event: NSEvent) -> Bool

    func flagsChanged(with event: NSEvent) -> Bool

    func magnify(with event: NSEvent) 

    func rotate(with event: NSEvent) 

    func swipe(with event: NSEvent) 

#elseif os(iOS) || os(tvOS) || os(visionOS)

    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) 

    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) 

    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) 

    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) 

#endif
}
