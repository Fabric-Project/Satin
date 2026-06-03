//
//  ParametricSurfacesRendererView.swift
//  Example
//
//  Created by OpenAI Codex on 6/3/26.
//

import Satin
import SwiftUI

struct ParametricSurfacesRendererView: View {
    let renderer = ParametricSurfacesRenderer()
    @State private var selectedSurface: String

    init() {
        _selectedSurface = State(initialValue: renderer.surfaceParam.value)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SatinMetalView(renderer: renderer)
                .ignoresSafeArea()
                .navigationTitle("Parametric Surfaces")

            Picker("Surface", selection: $selectedSurface) {
                ForEach(renderer.availableSurfaces, id: \.self) { title in
                    Text(title).tag(title)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(12)
            .onChange(of: selectedSurface) { _, value in
                renderer.surfaceParam.value = value
            }
        }
    }
}

struct ParametricSurfacesRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ParametricSurfacesRendererView()
    }
}
