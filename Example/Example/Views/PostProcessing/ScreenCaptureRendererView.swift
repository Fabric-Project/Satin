//
//  ScreenCaptureRendererView.swift
//  Example
//
//  Created by Reza Ali on 7/18/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

#if os(macOS)

import Foundation
import Satin
import SwiftUI

struct ScreenCaptureRendererView: View {
    var body: some View {
        SatinMetalView(renderer: ScreenCaptureRenderer())
            .ignoresSafeArea()
            .navigationTitle("Screen Capture")
    }
}

#if false
    #Preview {
        ScreenCaptureRendererView()
    }
#endif

#endif
