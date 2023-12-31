//
//  TextRendererView.swift
//  Example
//
//  Created by Reza Ali on 12/30/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Forge
import SwiftUI

struct SDFTextRendererView: View {
    var body: some View {
        ForgeView(renderer: SDFTextRenderer())
            .ignoresSafeArea()
            .navigationTitle("SDF Text")
    }
}

#Preview {
    TextRendererView()
}
