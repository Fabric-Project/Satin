//
//  Renderer2DView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Forge
import SwiftUI

struct TextRendererView: View {
    var body: some View {
        ForgeView(renderer: TextRenderer())
            .ignoresSafeArea()
            .navigationTitle("Text Geometry")
    }
}

struct TextRendererView_Previews: PreviewProvider {
    static var previews: some View {
        TextRendererView()
    }
}
