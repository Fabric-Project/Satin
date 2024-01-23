//
//  ShadowRendererView.swift
//  Example
//
//  Created by Reza Ali on 3/2/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct DirectionalShadowRendererView: View {
    var body: some View {
        SatinMetalView(renderer:  DirectionalShadowRenderer())
            .ignoresSafeArea()
            .navigationTitle("Directional Shadows")
    }
}

struct ShadowRendererView_Previews: PreviewProvider {
    static var previews: some View {
        DirectionalShadowRendererView()
    }
}
