//
//  ForgeViewRendererDelegate.swift
//  Forging
//
//  Created by Reza Ali on 1/22/24.
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
