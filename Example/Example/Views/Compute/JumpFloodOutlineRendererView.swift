//
//  JumpFloodOutlineRendererView.swift
//  Example
//
//  Created by Reza Ali on 6/29/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Foundation
import Satin
import SwiftUI

struct JumpFloodOutlineRendererView: View {
    var body: some View {
        SatinMetalView(renderer: JumpFloodOutlineRenderer())
            .ignoresSafeArea()
            .navigationTitle("Jump Flood Outline")
    }
}

#Preview {
    JumpFloodOutlineRendererView()
}
