//
//  PoissonRendererView.swift
//  Example
//
//  Created by Reza Ali on 11/9/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct PoissonRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PoissonRenderer())
            .ignoresSafeArea()
            .navigationTitle("Poisson Samples")
    }
}

#if false
    #Preview {
        PoissonRendererView()
    }
#endif
