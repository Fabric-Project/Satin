//
//  PointShadowRendererView.swift
//  Example
//
//  Created by OpenAI on 4/20/26.
//

import Satin
import SwiftUI

struct PointShadowRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PointShadowRenderer())
            .ignoresSafeArea()
            .navigationTitle("Point Shadows")
    }
}

struct PointShadowRendererView_Previews: PreviewProvider {
    static var previews: some View {
        PointShadowRendererView()
    }
}
