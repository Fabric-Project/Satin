//
//  SpotShadowRendererView.swift
//  Example
//
//  Created by OpenAI on 4/20/26.
//

import Satin
import SwiftUI

struct SpotShadowRendererView: View {
    var body: some View {
        SatinMetalView(renderer: SpotShadowRenderer())
            .ignoresSafeArea()
            .navigationTitle("Spot Shadows")
    }
}

struct SpotShadowRendererView_Previews: PreviewProvider {
    static var previews: some View {
        SpotShadowRendererView()
    }
}
