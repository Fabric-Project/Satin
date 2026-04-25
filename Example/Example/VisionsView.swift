//
//  VisionsView.swift
//  Example
//
//  Created by Reza Ali on 1/21/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

#if os(visionOS)

import SwiftUI

struct VisionsView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    enum ExampleType: String, Codable {
        case threed = "Immersive3D"
        case supershapes = "ImmersiveSuperShapes"
        case post = "ImmersivePost"
    }

    @State private var immersiveSpaceIsShown = false
    @State var example: ExampleType? = nil

    var body: some View {
        VStack {
            Button(action: {
                example = .threed
            }, label: {
                Text("Basic")
            })

            Button(action: {
                example = .supershapes
            }, label: {
                Text("Super Shapes")
            })

            Button(action: {
                example = .post
            }, label: {
                Text("Post")
            })

            Button(action: {
                example = nil
            }, label: {
                Text("Exit")
            })
        }

        .padding()
        .onChange(of: example, initial: false) {
            Task {
                if immersiveSpaceIsShown {
                    await dismissImmersiveSpace()
                    immersiveSpaceIsShown = false
                }

                if let example {
                    switch await openImmersiveSpace(id: example.rawValue) {
                        case .opened:
                            print("opened: \(example.rawValue)")
                            immersiveSpaceIsShown = true
                        case .error, .userCancelled:
                            print("error: \(example.rawValue)")
                            fallthrough
                        @unknown default:
                            print("default: \(example.rawValue)")
                            immersiveSpaceIsShown = false
                            self.example = nil
                    }
                }
            }
        }
    }
}

#Preview {
    VisionsView()
}

#endif
