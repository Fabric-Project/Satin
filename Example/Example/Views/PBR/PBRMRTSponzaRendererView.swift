//
//  PBRMRTSponzaRendererView.swift
//  Example
//
//  Created by OpenAI Codex on 4/26/26.
//

import Satin
import SwiftUI

struct PBRMRTSponzaRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PBRMRTSponzaRenderer())
            .navigationTitle("Deferred Rendering Sponza")
    }
}

struct PBRMRTSponzaRendererView_Previews: PreviewProvider {
    static var previews: some View {
        PBRMRTSponzaRendererView()
    }
}
