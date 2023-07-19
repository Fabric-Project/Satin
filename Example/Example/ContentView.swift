//
//  ContentView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Forge
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                Group {
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

                        NavigationLink(destination: ARSatinSceneKitRendererView()) {
                            Label("AR + Satin + SceneKit", systemImage: "arkit")
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
                    }

                    Section(header: Text("Materials")) {
                        NavigationLink(destination: CubemapRendererView()) {
                            Label("Skybox Material", systemImage: "map")
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
                        NavigationLink(destination: TextRendererView()) {
                            Label("Text", systemImage: "textformat")
                        }

                        NavigationLink(destination: ExtrudedTextRendererView()) {
                            Label("Extruded Text", systemImage: "square.3.layers.3d.down.right")
                        }

                        NavigationLink(destination: SuperShapesRendererView()) {
                            Label("Super Shapes", systemImage: "seal")
                        }

                        NavigationLink(destination: LoadObjRendererView()) {
                            Label("Obj Loading", systemImage: "arrow.down.doc")
                        }

                        NavigationLink(destination: OctasphereRendererView()) {
                            Label("Octasphere", systemImage: "globe")
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
                }

                Group {
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

                        NavigationLink(destination: SatinSceneKitRendererView()) {
                            Label("Satin + SceneKit", systemImage: "plus")
                        }

                        NavigationLink(destination: TessellationRendererView()) {
                            Label("Tessellation", systemImage: "square.split.2x2")
                        }
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

                        NavigationLink(destination: FXAARendererView()) {
                            Label("FXAA", systemImage: "squareshape.split.2x2.dotted")
                        }
                    }
                }
            }
            .navigationTitle("Satin Examples")

//            BufferGeometryRendererView()
//            MatcapRendererView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
