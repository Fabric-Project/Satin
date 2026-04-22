//
//  PBRMRTRendererView.swift
//  Example
//
//  Created by OpenAI Codex on 4/22/26.
//

import Satin
import SwiftUI

struct PBRMRTRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PBRMRTRenderer())
            .ignoresSafeArea()
            .navigationTitle("Deferred Rendering")
    }
}

struct PBRMRTRendererView_Previews: PreviewProvider {
    static var previews: some View {
        PBRMRTRendererView()
    }
}
