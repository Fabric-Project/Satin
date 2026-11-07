//
//  StrokeRendererView.swift
//  Example
//

import Satin
import SwiftUI

struct StrokeRendererView: View {
    var body: some View {
        SatinMetalView(renderer: StrokeRenderer())
            .ignoresSafeArea()
            .navigationTitle("Strokes")
    }
}
