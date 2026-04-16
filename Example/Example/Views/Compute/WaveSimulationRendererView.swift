//
//  WaveSimulationRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/10/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct WaveSimulationRendererView: View {
    var body: some View {
        SatinMetalView(renderer: WaveSimulationRenderer())
            .ignoresSafeArea()
            .navigationTitle("Wave Simulation")
    }
}

#if false
    #Preview {
        WaveSimulationRendererView()
    }
#endif
