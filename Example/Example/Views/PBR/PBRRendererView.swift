//
//  PBRRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct PBRRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PBRRenderer())
            .ignoresSafeArea()
            .navigationTitle("Physically Based Rendering")
    }
}

struct PBRRendererView_Previews: PreviewProvider {
    static var previews: some View {
        PBRRendererView()
    }
}
