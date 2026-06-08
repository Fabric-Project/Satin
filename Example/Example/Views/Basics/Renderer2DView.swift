//
//  Renderer2DView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct Renderer2DView: View {
    var body: some View {
        SatinMetalView(renderer: Renderer2D())
            .ignoresSafeArea()
            .navigationTitle("2D")
    }
}

#if false
    #Preview {
        Renderer2DView()
    }
#endif
