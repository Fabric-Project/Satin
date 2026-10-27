//
//  ARPeopleOcclusionRendererView.swift
//  Example
//
//  Created by Reza Ali on 4/11/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Satin
import SwiftUI

struct ARPeopleOcclusionRendererView: View {
    var body: some View {
        SatinMetalView(renderer: ARPeopleOcclusionRenderer(context: .makePlatformDefault()))
            .ignoresSafeArea()
            .navigationTitle("AR People Occlusion")
    }
}

struct ARPeopleOcclusionRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ARPeopleOcclusionRendererView()
    }
}

#endif
