//
//  ARRendererView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

#if os(iOS)

import Satin
import SwiftUI

struct ARDrawingRendererView: View {
    let renderer = ARDrawingRenderer()
    var body: some View {
        SatinMetalView(renderer: renderer)
            .ignoresSafeArea()
            .navigationTitle("AR Drawing")
            .overlay {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            renderer.clear()
                        }, label: {
                            Image(systemName: "eraser.fill")
                                .renderingMode(.template)
                                .imageScale(.large)
                                .foregroundColor(.white)
                                .padding(16)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        })
                        .padding(16)
                    }
                }
            }
    }
}

struct ARDrawingRendererView_Previews: PreviewProvider {
    static var previews: some View {
        ARDrawingRendererView()
    }
}

#endif
