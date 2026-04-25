//
//  GridRendererView.swift
//  Example
//
//  Created by Reza Ali on 9/3/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import SwiftUI

struct GridRendererView: View {
    var body: some View {
        SatinMetalView(renderer: GridRenderer())
            .ignoresSafeArea()
            .navigationTitle("Grid")
    }
}

#Preview {
    GridRendererView()
}
