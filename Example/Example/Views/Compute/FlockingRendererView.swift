//
//  FlockingRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/17/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct FlockingRendererView: View {
    var body: some View {
        SatinMetalView(renderer: FlockingRenderer())
            .ignoresSafeArea()
            .navigationTitle("Flocking Particles")
    }
}

struct FlockingRendererView_Previews: PreviewProvider {
    static var previews: some View {
        FlockingRendererView()
    }
}
