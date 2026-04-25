//
//  BufferGeometryRendererView.swift
//  Example
//
//  Created by Reza Ali on 7/13/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct BufferGeometryRendererView: View {
    var body: some View {
        SatinMetalView(renderer: BufferGeometryRenderer())
            .ignoresSafeArea()
            .navigationTitle("Buffer Geometry")
    }
}

#Preview {
    BufferGeometryRendererView()
}
