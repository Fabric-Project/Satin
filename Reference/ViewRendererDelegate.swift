//
//  ViewRendererDelegate.swift
//  Satin
//

import Foundation
import QuartzCore

#if canImport(AppKit)
import AppKit
#endif

protocol ViewRendererDelegate: AnyObject {
    var id: String { get }
    func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable)
    func drawableResized(size: CGSize, scaleFactor: CGFloat)
}
