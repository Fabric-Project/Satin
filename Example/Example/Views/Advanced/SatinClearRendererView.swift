//
//  SatinClearRendererView.swift
//  Example
//
//  Created by OpenAI on 4/19/26.
//

#if os(macOS)

import Metal
import Satin
import SwiftUI

struct SatinClearAView: View {
    var body: some View {
        SatinMetalView(
            renderer: SatinClearRenderer(
                clearColor: MTLClearColor(red: 0.18, green: 0.58, blue: 0.30, alpha: 1.0)
            )
        )
        .ignoresSafeArea()
        .navigationTitle("Satin Clear A")
    }
}

struct SatinClearBView: View {
    var body: some View {
        SatinMetalView(
            renderer: SatinClearRenderer(
                clearColor: MTLClearColor(red: 0.75, green: 0.45, blue: 0.12, alpha: 1.0)
            )
        )
        .ignoresSafeArea()
        .navigationTitle("Satin Clear B")
    }
}

#if false
    #Preview {
        SatinClearAView()
    }
#endif

#endif
