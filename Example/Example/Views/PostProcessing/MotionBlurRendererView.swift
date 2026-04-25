//
//  MotionBlurRendererView.swift
//  Example
//
//  Created by Reza Ali on 4/20/25.
//  Copyright © 2025 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct MotionBlurRendererView: View {
    var body: some View {
        SatinMetalView(renderer: MotionBlurRenderer())
            .ignoresSafeArea()
            .navigationTitle("Motion Blur")
    }
}

#if false
    #Preview {
        MotionBlurRendererView()
    }
#endif
