//
//  DiskRendererView.swift
//  Example
//
//  Created by Reza Ali on 10/15/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct DiskRendererView: View {
    var body: some View {
        SatinMetalView(renderer: DiskRenderer())
            .ignoresSafeArea()
            .navigationTitle("UV Disk")
    }
}

#Preview {
    DiskRendererView()
}

