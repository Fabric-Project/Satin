//
//  EnhancedPBRRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct PBREnhancedRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PBREnhancedRenderer())
            .ignoresSafeArea()
            .navigationTitle("PBR Physical Point Shadows")
    }
}

struct PBREnhancedRendererView_Previews: PreviewProvider {
    static var previews: some View {
        PBREnhancedRendererView()
    }
}
