//
//  ForgeView.swift
//  Forging
//
//  Created by Reza Ali on 1/21/24.
//

import Foundation
import SwiftUI

#if os(macOS)

public struct SatinMetalView: NSViewControllerRepresentable {
    public var renderer: any MetalViewRendererDelegate

    public init(renderer: any MetalViewRendererDelegate) {

        print("SatinMetalView SwiftUI Initializer renderer id: \(renderer.id)")

        self.renderer = renderer

    }

    public func makeNSViewController(context: Self.Context) -> MetalViewController {
        print("SatinMetalView SwiftUI makeNSViewController renderer id: \(renderer.id)")

        return MetalViewController(renderer: renderer)
    }

    public func updateNSViewController(_ nsViewController: Self.NSViewControllerType, context: Self.Context) {}
}

#elseif os(iOS) || os(tvOS) || os(visionOS)

public struct SatinMetalView: UIViewControllerRepresentable {
    public var renderer: MetalViewRenderer

    public init(renderer: MetalViewRenderer) {
        self.renderer = renderer
    }

    public func makeUIViewController(context: Self.Context) -> MetalViewController {
        MetalViewController(renderer: renderer)
    }

    public func updateUIViewController(_ uiViewController: MetalViewController, context: Self.Context) {}
}

#endif
