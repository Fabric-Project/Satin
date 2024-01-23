//
//  ARContactShadowRendererView.swift
//  Example
//
//  Created by Reza Ali on 3/22/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Satin
import SwiftUI

struct ARContactShadowRendererView: View {
    var body: some View {
        SatinMetalView(renderer: ARContactShadowRenderer())
            .ignoresSafeArea()
            .navigationTitle("AR Contact Shadow")
    }
}

struct ARContactShadowRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ARContactShadowRendererView()
    }
}

#endif
