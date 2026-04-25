//
//  RadianceCascadesRendererView.swift
//  Example
//
//  Created by Reza Ali on 12/8/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct RadianceCascadesRendererView: View {
    var body: some View {
        SatinMetalView(renderer: RadianceCascadesRenderer())
            .ignoresSafeArea()
            .navigationTitle("Radiance Cascades")
    }
}

#Preview{
    RadianceCascadesRendererView()
}
