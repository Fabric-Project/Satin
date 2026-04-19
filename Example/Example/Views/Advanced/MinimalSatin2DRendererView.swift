//
//  MinimalSatin2DRendererView.swift
//  Example
//
//  Created by OpenAI on 4/19/26.
//

#if os(macOS)

import Satin
import SwiftUI

struct MinimalSatin2DRendererView: View {
    var body: some View {
        SatinMetalView(renderer: MinimalSatin2DRenderer())
            .ignoresSafeArea()
            .navigationTitle("Minimal Satin 2D")
    }
}

#if false
    #Preview {
        MinimalSatin2DRendererView()
    }
#endif

#endif
