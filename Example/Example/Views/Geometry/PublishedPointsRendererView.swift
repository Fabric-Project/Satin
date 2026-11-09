//
//  PublishedPointsRendererView.swift
//  Example
//

import Satin
import SwiftUI

struct PublishedPointsRendererView: View {
    var body: some View {
        SatinMetalView(renderer: PublishedPointsRenderer())
            .ignoresSafeArea()
            .navigationTitle("Published Points")
    }
}
