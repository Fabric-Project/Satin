//
//  StandardMaterialRendererView.swift
//  Example
//
//  Created by Reza Ali on 11/11/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct PBRStandardMaterialRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PBRStandardMaterialRenderer())
            .ignoresSafeArea()
            .navigationTitle("PBR Standard Material")
    }
}

struct PBRStandardMaterialRendererView_Previews: PreviewProvider {
    static var previews: some View {
        PBRStandardMaterialRendererView()
    }
}
