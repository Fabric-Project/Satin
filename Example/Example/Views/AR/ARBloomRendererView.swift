//
//  ARBloomRendererView.swift
//  Example
//
//  Created by Reza Ali on 4/26/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Satin
import SwiftUI

struct ARBloomRendererView: View {
    var body: some View {
        SatinMetalView(renderer: ARBloomRenderer(context: .makePlatformDefault()))
            .ignoresSafeArea()
            .navigationTitle("AR Bloom")
    }
}

struct ARBloomRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ARBloomRendererView()
    }
}

#endif
