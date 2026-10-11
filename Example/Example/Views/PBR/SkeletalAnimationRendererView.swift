//
//  SkeletalAnimationRendererView.swift
//  Example
//

import Satin
import SwiftUI

struct SkeletalAnimationRendererView: View {
    var body: some View {
        SatinMetalView(renderer: SkeletalAnimationRenderer())
            .ignoresSafeArea()
            .navigationTitle("Skeletal Animation")
    }
}

struct SkeletalAnimationRendererView_Previews: PreviewProvider {
    static var previews: some View {
        SkeletalAnimationRendererView()
    }
}
