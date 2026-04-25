//
//  ContentView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                #if os(visionOS)
                    Section(header: Text("Vision")) {
                        NavigationLink(destination: VisionsView()) {
                            Label("Immersive", systemImage: "visionpro")
                        }
                    }
                #endif
                #if os(iOS)
                    Section(header: Text("AR")) {
                        NavigationLink(destination: ARRendererView()) {
                            Label("AR Hello World", systemImage: "arkit")
                        }

                        NavigationLink(destination: ARContactShadowRendererView()) {
                            Label("AR Contact Shadow", systemImage: "square.2.layers.3d.bottom.filled")
                        }

                        NavigationLink(destination: ARDrawingRendererView()) {
                            Label("AR Drawing", systemImage: "scribble.variable")
                        }

                        NavigationLink(destination: ARBloomRendererView()) {
                            Label("AR Bloom", systemImage: "sun.max.circle")
                        }

                        NavigationLink(destination: ARLidarMeshRendererView()) {
                            Label("AR Lidar Mesh", systemImage: "point.3.filled.connected.trianglepath.dotted")
                        }

                        NavigationLink(destination: ARPBRRendererView()) {
                            Label("AR PBR", systemImage: "party.popper")
                        }

                        NavigationLink(destination: ARPeopleOcclusionRendererView()) {
                            Label("AR People Occlusion", systemImage: "person.2.fill")
                        }

                        NavigationLink(destination: ARPlanesRendererView()) {
                            Label("AR Planes", systemImage: "squareshape")
                        }

                        NavigationLink(destination: ARPointCloudRendererView()) {
                            Label("AR Point Cloud", systemImage: "cloud")
                        }
                    }
                #endif

                Section(header: Text("Basics")) {
                    NavigationLink(destination: Renderer2DView()) {
                        Label("2D", systemImage: "square")
                    }

                    NavigationLink(destination: Renderer3DView()) {
                        Label("3D", systemImage: "cube")
                    }

                    NavigationLink(destination: InstancedMeshRendererView()) {
                        Label("Instanced Mesh", systemImage: "circle.grid.2x2.fill")
                    }

                    NavigationLink(destination: CameraControllerRendererView()) {
                        Label("Camera Controller", systemImage: "camera.aperture")
                    }

                    NavigationLink(destination: OrbitCameraControllerRendererView()) {
                        Label("Orbit Camera Controller", systemImage: "rotate.3d.circle")
                    }
                }

                Section(header: Text("Text")) {
                    NavigationLink(destination: SDFTextRendererView()) {
                        Label("SDF Text", systemImage: "f.cursive")
                    }

                    NavigationLink(destination: TextRendererView()) {
                        Label("Text Geometry", systemImage: "textformat")
                    }

                    NavigationLink(destination: ExtrudedTextRendererView()) {
                        Label("Extruded Text", systemImage: "square.3.layers.3d.down.right")
                    }
                }

                Section(header: Text("Materials")) {
                    NavigationLink(destination: CubemapRendererView()) {
                        Label("Skybox Material", systemImage: "map")
                    }

                    NavigationLink(destination: GridRendererView()) {
                        Label("Grid Material", systemImage: "grid")
                    }

                    NavigationLink(destination: MatcapRendererView()) {
                        Label("Matcap Material", systemImage: "graduationcap")
                    }

                    NavigationLink(destination: DepthMaterialRendererView()) {
                        Label("Depth Material", systemImage: "rectangle.stack")
                    }

                    NavigationLink(destination: OcclusionRendererView()) {
                        Label("Occlusion Material", systemImage: "moonphase.first.quarter.inverse")
                    }

                    NavigationLink(destination: LiveCodeRendererView()) {
                        Label("Live Material", systemImage: "doc.text")
                    }
                }

                Section(header: Text("Geometry")) {
                    NavigationLink(destination: SuperShapesRendererView()) {
                        Label("Super Shapes", systemImage: "seal")
                    }

                    NavigationLink(destination: LoadObjRendererView()) {
                        Label("Obj Loading", systemImage: "arrow.down.doc")
                    }

                    NavigationLink(destination: OctasphereRendererView()) {
                        Label("Octasphere", systemImage: "globe")
                    }

                    NavigationLink(destination: DiskRendererView()) {
                        Label("UV Disk", systemImage: "hexagon.fill")
                    }

                    NavigationLink(destination: ExportGeometryRendererView()) {
                        Label("Export Geometry", systemImage: "square.and.arrow.up")
                    }
                }

                Section(header: Text("Customization")) {
                    NavigationLink(destination: CustomGeometryRendererView()) {
                        Label("Custom Geometry", systemImage: "network")
                    }

                    NavigationLink(destination: CustomInstancingRendererView()) {
                        Label("Custom Instancing", systemImage: "square.grid.3x3")
                    }

                    NavigationLink(destination: VertexAttributesRendererView()) {
                        Label("Custom Vertex Attributes", systemImage: "asterisk.circle")
                    }
                }

                Section(header: Text("Compute")) {
                    NavigationLink(destination: BufferComputeRendererView()) {
                        Label("Buffer Compute", systemImage: "aqi.medium")
                    }

                    NavigationLink(destination: FlockingRendererView()) {
                        Label("Flocking Particles", systemImage: "bird")
                    }

                    NavigationLink(destination: TextureComputeRendererView()) {
                        Label("Texture Compute", systemImage: "photo.stack")
                    }

                    NavigationLink(destination: WaveSimulationRendererView()) {
                        Label("Wave Simulation", systemImage: "water.waves")
                    }

                    NavigationLink(destination: JumpFloodOutlineRendererView()) {
                        Label("Jump Flood Outline", systemImage: "squareshape.split.3x3")
                    }
                }

                Section(header: Text("Shadows")) {
                    NavigationLink(destination: ContactShadowRendererView()) {
                        Label("Contact Shadow", systemImage: "square.2.layers.3d.bottom.filled")
                    }

                    NavigationLink(destination: DirectionalShadowRendererView()) {
                        Label("Directional Shadow", systemImage: "shadow")
                    }

                    NavigationLink(destination: ProjectedShadowRendererView()) {
                        Label("Projected Shadow", systemImage: "shadow")
                    }
                }

                Section(header: Text("Advanced")) {
                    #if os(macOS)
                        NavigationLink(destination: AudioInputRendererView()) {
                            Label("Audio Input", systemImage: "mic")
                        }
                    #endif
                    if let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(MTLGPUFamily.mac2) || device.supportsFamily(MTLGPUFamily.apple8) {
                        NavigationLink(destination: MeshShaderRendererView()) {
                            Label("Mesh Shader", systemImage: "circle.hexagongrid.fill")
                        }
                    }

                    NavigationLink(destination: BufferGeometryRendererView()) {
                        Label("Buffer Geometry", systemImage: "camera.metering.multispot")
                    }

                    NavigationLink(destination: RayMarchingRendererView()) {
                        Label("Ray Marching", systemImage: "camera.metering.multispot")
                    }

                    NavigationLink(destination: MultipleContextRendererView()) {
                        Label("Multiple Context", systemImage: "rectangle.split.2x1")
                    }

                    #if !targetEnvironment(simulator)
                        NavigationLink(destination: MultipleViewportRendererView()) {
                            Label("Vertex Amplification", systemImage: "rectangle.split.2x1")
                        }
                        NavigationLink(destination: TessellationRendererView()) {
                            Label("Tessellation", systemImage: "square.split.2x2")
                        }
                    #endif
                }

                Section(header: Text("Physically Based Rendering")) {
                    NavigationLink(destination: PBRRendererView()) {
                        Label("PBR", systemImage: "eye")
                    }

                    NavigationLink(destination: PBRCustomizationRendererView()) {
                        Label("PBR Customization", systemImage: "gear")
                    }

                    NavigationLink(destination: PBREnhancedRendererView()) {
                        Label("PBR Physical Material", systemImage: "party.popper")
                    }

                    NavigationLink(destination: PBRStandardMaterialRendererView()) {
                        Label("PBR Standard Material", systemImage: "flame")
                    }

                    NavigationLink(destination: PBRSubmeshRendererView()) {
                        Label("PBR Submeshes", systemImage: "soccerball")
                    }
                }

                Section(header: Text("Post Processing")) {
                    NavigationLink(destination: PostProcessingRendererView()) {
                        Label("Post Processing", systemImage: "checkerboard.rectangle")
                    }

                    NavigationLink(destination: BloomRendererView()) {
                        Label("Bloom", systemImage: "sun.max.fill")
                    }

                    NavigationLink(destination: FXAARendererView()) {
                        Label("FXAA", systemImage: "squareshape.split.2x2.dotted")
                    }
                    #if os(macOS)
                        NavigationLink(destination: ScreenCaptureRendererView()) {
                            Label("Screen Capture", systemImage: "display.and.arrow.down")
                        }
                    #endif
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Satin Examples")
            #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: toggleSidebar, label: { // 1
                            Image(systemName: "sidebar.leading")
                        })
                    }
                }
            #endif

            #if os(macOS)
                PBRStandardMaterialRendererView()
            #endif
        }
    }

    #if os(macOS)
        private func toggleSidebar() {
            NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        }
    #endif
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
