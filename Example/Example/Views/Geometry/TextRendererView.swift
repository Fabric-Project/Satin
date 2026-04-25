//
//  Renderer2DView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct TextRendererView: View {
    let renderer: TextRenderer
    @State private var selectedFont: String

    init() {
        let r = TextRenderer()
        renderer = r
        _selectedFont = State(initialValue: r.fontParam.value)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SatinMetalView(renderer: renderer)
                .ignoresSafeArea()
                .navigationTitle("Text Geometry")

            Picker("Font", selection: $selectedFont) {
                ForEach(renderer.fontParam.options, id: \.self) { font in
                    Text(font).tag(font)
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }
        .onChange(of: selectedFont) { newValue in
            renderer.fontParam.value = newValue
        }
    }
}

struct TextRendererView_Previews: PreviewProvider {
    static var previews: some View {
        TextRendererView()
    }
}
