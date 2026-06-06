//
//  ParametricSurfacesRendererView.swift
//  Example
//
//  Created by OpenAI Codex on 6/3/26.
//

import Satin
import SwiftUI

struct ParametricSurfacesRendererView: View {
    var body: some View {
        SatinMetalView(renderer: ParametricSurfacesRenderer())
            .ignoresSafeArea()
            .navigationTitle("Parametric Surfaces")
    }
}

struct ParametricSurfacesRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ParametricSurfacesRendererView()
    }
}
