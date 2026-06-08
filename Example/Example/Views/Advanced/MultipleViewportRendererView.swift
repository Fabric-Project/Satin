//
//  MultipleViewportRendererView.swift
//  Example
//
//  Created by Reza Ali on 2/4/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct MultipleViewportRendererView: View {
    var body: some View {
        SatinMetalView(renderer: MultipleViewportRenderer())
            .ignoresSafeArea()
            .navigationTitle("Multiple Viewports")
    }
}

#if false
    #Preview {
        MultipleViewportRendererView()
    }
#endif
