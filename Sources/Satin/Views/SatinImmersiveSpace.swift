//
//  SatinImmersiveSpace.swift
//
//
//  Created by Reza Ali on 1/23/24.
//

#if os(visionOS)

import CompositorServices
import Foundation
import SwiftUI

public struct SatinImmersiveSpace: SwiftUI.Scene {
    private let renderer: SpatialRenderer

    @Binding private var immersionStyle: ImmersionStyle

    public init(renderer: SpatialRenderer, immersionStyle: Binding<ImmersionStyle>) {
        self.renderer = renderer
        _immersionStyle = immersionStyle
    }

    public var body: some SwiftUI.Scene {
        ImmersiveSpace(id: renderer.id) {
            CompositorLayer(configuration: renderer) { layerRenderer in
                renderer.layerRenderer = layerRenderer
                if !renderer.isSetup {
                    renderer.setup()
                    renderer.isSetup = true
                    renderer.startARSession()
                }
                renderer.startRenderLoop()
            }
        }.immersionStyle(selection: $immersionStyle, in: .mixed, .full)
    }
}

#endif
