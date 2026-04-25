//
//  MultipleContextRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/4/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct MultipleContextRendererView: View {
    var body: some View {
        SatinMetalView(renderer: MultipleContextRenderer())
            .ignoresSafeArea()
            .navigationTitle("Multiple Contexts")
    }
}

#Preview {
    MultipleContextRendererView()
}


