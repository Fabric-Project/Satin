//
//  SlugTextRendererView.swift
//
//
//  Created by OpenAI on 4/25/26.
//

import Satin
import SwiftUI

struct SlugTextRendererView: View {
    var body: some View {
        SatinMetalView(renderer: SlugTextRenderer())
            .ignoresSafeArea()
            .navigationTitle("SLUG Text")
    }
}

#if false
    #Preview {
        SlugTextRendererView()
    }
#endif
