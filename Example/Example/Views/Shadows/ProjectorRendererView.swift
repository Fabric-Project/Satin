//
//  ProjectorRendererView.swift
//  Example
//
//  Created by OpenAI on 4/20/26.
//

import Satin
import SwiftUI

struct ProjectorRendererView: View {
    var body: some View {
        SatinMetalView(renderer: ProjectorRenderer())
            .ignoresSafeArea()
            .navigationTitle("Projector")
    }
}

struct ProjectorRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ProjectorRendererView()
    }
}
