//
//  PolylineRendererView.swift
//  Example
//

import Satin
import SwiftUI

struct PolylineRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PolylineRenderer())
            .ignoresSafeArea()
            .navigationTitle("Polylines")
    }
}
