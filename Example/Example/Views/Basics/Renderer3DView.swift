//
//  Renderer3DView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct Renderer3DView: View {
    var body: some View {
        SatinMetalView(renderer: Renderer3D())
            .ignoresSafeArea()
            .navigationTitle("3D")
    }
}

struct Renderer3DView_Previews: PreviewProvider {
    static var previews: some View {
        Renderer3DView()
    }
}
