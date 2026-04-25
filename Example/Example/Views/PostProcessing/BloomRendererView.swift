//
//  BloomRendererView.swift
//  Example
//
//  Created by Reza Ali on 9/2/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct BloomRendererView: View {
    var body: some View {
        SatinMetalView(renderer: BloomRenderer())
            .ignoresSafeArea()
            .navigationTitle("Bloom")
    }
}

#Preview {
    BloomRendererView()
}
