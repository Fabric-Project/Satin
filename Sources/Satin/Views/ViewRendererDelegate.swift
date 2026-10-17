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

public protocol ErrorRenderDelegate: AnyObject {
    func renderer(_ renderer: Renderer, didFailWith error: any Error)
}

protocol ViewRendererDelegate: AnyObject {
    var id: String { get }
    /// `hostTime` is the host time (`CACurrentMediaTime`) the frame targets;
    /// `presentationHostTime` is when it is expected on screen, nil when unknown.
    func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable, hostTime: TimeInterval, presentationHostTime: TimeInterval?)
    func drawableResized(size: CGSize, scaleFactor: CGFloat)
}
