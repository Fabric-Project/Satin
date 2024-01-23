//
//  LoadObjRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Satin
import SwiftUI

struct LoadObjRendererView: View {
    var body: some View {
        SatinMetalView(renderer: LoadObjRenderer())
            .ignoresSafeArea()
            .navigationTitle("Obj Loading")
    }
}

struct LoadObjRendererView_Previews: PreviewProvider {
    static var previews: some View {
        LoadObjRendererView()
    }
}
