//
//  ContentView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Metal
import SwiftUI

private struct ExampleItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let makeView: () -> AnyView

    init<V: View>(id: String, title: String, systemImage: String, @ViewBuilder destination: @escaping () -> V) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.makeView = { AnyView(destination()) }
    }
}

private struct ExampleSection: Identifiable {
    let id: String
    let title: String
    let items: [ExampleItem]

    init(title: String, items: [ExampleItem]) {
        self.id = title
        self.title = title
        self.items = items
    }
}

struct ContentView: View {
    #if os(macOS)
        @State private var selection: String? = "pbr-standard-material"
    #else
        @State private var selection: String?
    #endif

    private var sections: [ExampleSection] {
        var results: [ExampleSection] = []

        #if os(visionOS)
            results.append(
                ExampleSection(
                    title: "Vision",
                    items: [
                        ExampleItem(id: "vision-immersive", title: "Immersive", systemImage: "visionpro") {
                            VisionsView()
                        }
                    ]
                )
            )
        #endif

        #if os(iOS)
            results.append(
                ExampleSection(
                    title: "AR",
                    items: [
                        ExampleItem(id: "ar-hello-world", title: "AR Hello World", systemImage: "arkit") { ARRendererView() },
                        ExampleItem(id: "ar-contact-shadow", title: "AR Contact Shadow", systemImage: "square.2.layers.3d.bottom.filled") { ARContactShadowRendererView() },
                        ExampleItem(id: "ar-drawing", title: "AR Drawing", systemImage: "scribble.variable") { ARDrawingRendererView() },
                        ExampleItem(id: "ar-bloom", title: "AR Bloom", systemImage: "sun.max.circle") { ARBloomRendererView() },
                        ExampleItem(id: "ar-lidar-mesh", title: "AR Lidar Mesh", systemImage: "point.3.filled.connected.trianglepath.dotted") { ARLidarMeshRendererView() },
                        ExampleItem(id: "ar-pbr", title: "AR PBR", systemImage: "party.popper") { ARPBRRendererView() },
                        ExampleItem(id: "ar-people-occlusion", title: "AR People Occlusion", systemImage: "person.2.fill") { ARPeopleOcclusionRendererView() },
                        ExampleItem(id: "ar-planes", title: "AR Planes", systemImage: "squareshape") { ARPlanesRendererView() },
                        ExampleItem(id: "ar-point-cloud", title: "AR Point Cloud", systemImage: "cloud") { ARPointCloudRendererView() }
                    ]
                )
            )
        #endif

        results.append(
            ExampleSection(
                title: "Basics",
                items: [
                    ExampleItem(id: "2d", title: "2D", systemImage: "square") { Renderer2DView() },
                    ExampleItem(id: "3d", title: "3D", systemImage: "cube") { Renderer3DView() },
                    ExampleItem(id: "instanced-mesh", title: "Instanced Mesh", systemImage: "circle.grid.2x2.fill") { InstancedMeshRendererView() },
                    ExampleItem(id: "camera-controller", title: "Camera Controller", systemImage: "camera.aperture") { CameraControllerRendererView() },
                    ExampleItem(id: "orbit-camera-controller", title: "Orbit Camera Controller", systemImage: "rotate.3d.circle") { OrbitCameraControllerRendererView() }
                ]
            )
        )

        results.append(
            ExampleSection(
                title: "Text",
                items: [
                    ExampleItem(id: "sdf-text", title: "SDF Text", systemImage: "f.cursive") { SDFTextRendererView() },
                    ExampleItem(id: "text-geometry", title: "Text Geometry", systemImage: "textformat") { TextRendererView() },
                    ExampleItem(id: "extruded-text", title: "Extruded Text", systemImage: "square.3.layers.3d.down.right") { ExtrudedTextRendererView() }
                ]
            )
        )

        results.append(
            ExampleSection(
                title: "Materials",
                items: [
                    ExampleItem(id: "skybox-material", title: "Skybox Material", systemImage: "map") { CubemapRendererView() },
                    ExampleItem(id: "grid-material", title: "Grid Material", systemImage: "grid") { GridRendererView() },
                    ExampleItem(id: "matcap-material", title: "Matcap Material", systemImage: "graduationcap") { MatcapRendererView() },
                    ExampleItem(id: "depth-material", title: "Depth Material", systemImage: "rectangle.stack") { DepthMaterialRendererView() },
                    ExampleItem(id: "occlusion-material", title: "Occlusion Material", systemImage: "moonphase.first.quarter.inverse") { OcclusionRendererView() },
                    ExampleItem(id: "live-material", title: "Live Material", systemImage: "doc.text") { LiveCodeRendererView() }
                ]
            )
        )

        results.append(
            ExampleSection(
                title: "Geometry",
                items: [
                    ExampleItem(id: "super-shapes", title: "Super Shapes", systemImage: "seal") { SuperShapesRendererView() },
                    ExampleItem(id: "obj-loading", title: "Obj Loading", systemImage: "arrow.down.doc") { LoadObjRendererView() },
                    ExampleItem(id: "octasphere", title: "Octasphere", systemImage: "globe") { OctasphereRendererView() },
                    ExampleItem(id: "uv-disk", title: "UV Disk", systemImage: "hexagon.fill") { DiskRendererView() },
                    ExampleItem(id: "export-geometry", title: "Export Geometry", systemImage: "square.and.arrow.up") { ExportGeometryRendererView() }
                ]
            )
        )

        results.append(
            ExampleSection(
                title: "Customization",
                items: [
                    ExampleItem(id: "custom-geometry", title: "Custom Geometry", systemImage: "network") { CustomGeometryRendererView() },
                    ExampleItem(id: "custom-instancing", title: "Custom Instancing", systemImage: "square.grid.3x3") { CustomInstancingRendererView() },
                    ExampleItem(id: "custom-vertex-attributes", title: "Custom Vertex Attributes", systemImage: "asterisk.circle") { VertexAttributesRendererView() }
                ]
            )
        )

        results.append(
            ExampleSection(
                title: "Compute",
                items: [
                    ExampleItem(id: "buffer-compute", title: "Buffer Compute", systemImage: "aqi.medium") { BufferComputeRendererView() },
                    ExampleItem(id: "flocking-particles", title: "Flocking Particles", systemImage: "bird") { FlockingRendererView() },
                    ExampleItem(id: "texture-compute", title: "Texture Compute", systemImage: "photo.stack") { TextureComputeRendererView() },
                    ExampleItem(id: "wave-simulation", title: "Wave Simulation", systemImage: "water.waves") { WaveSimulationRendererView() },
                    ExampleItem(id: "jump-flood-outline", title: "Jump Flood Outline", systemImage: "squareshape.split.3x3") { JumpFloodOutlineRendererView() }
                ]
            )
        )

        results.append(
            ExampleSection(
                title: "Shadows",
                items: [
                    ExampleItem(id: "contact-shadow", title: "Contact Shadow (Utility)", systemImage: "square.2.layers.3d.bottom.filled") { ContactShadowRendererView() },
                    ExampleItem(id: "directional-shadow", title: "Directional Shadow", systemImage: "shadow") { DirectionalShadowRendererView() },
                    ExampleItem(id: "point-shadow", title: "Point Shadows", systemImage: "lightbulb.2") { PointShadowRendererView() },
                    ExampleItem(id: "projected-shadow", title: "Projected Shadow (Utility)", systemImage: "shadow") { ProjectedShadowRendererView() }
                ]
            )
        )

        var advancedItems: [ExampleItem] = []
        #if os(macOS)
            advancedItems.append(
                ExampleItem(id: "audio-input", title: "Audio Input", systemImage: "mic") {
                    AudioInputRendererView()
                }
            )
        #endif
        if let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(MTLGPUFamily.mac2) || device.supportsFamily(MTLGPUFamily.apple8) {
            advancedItems.append(
                ExampleItem(id: "mesh-shader", title: "Mesh Shader", systemImage: "circle.hexagongrid.fill") {
                    MeshShaderRendererView()
                }
            )
        }
        advancedItems.append(
            contentsOf: [
                ExampleItem(id: "buffer-geometry", title: "Buffer Geometry", systemImage: "camera.metering.multispot") { BufferGeometryRendererView() },
                ExampleItem(id: "ray-marching", title: "Ray Marching", systemImage: "camera.metering.multispot") { RayMarchingRendererView() },
                ExampleItem(id: "multiple-context", title: "Multiple Context", systemImage: "rectangle.split.2x1") { MultipleContextRendererView() }
            ]
        )
        #if !targetEnvironment(simulator)
            advancedItems.append(
                contentsOf: [
                    ExampleItem(id: "vertex-amplification", title: "Vertex Amplification", systemImage: "rectangle.split.2x1") { MultipleViewportRendererView() },
                    ExampleItem(id: "tessellation", title: "Tessellation", systemImage: "square.split.2x2") { TessellationRendererView() }
                ]
            )
        #endif
        results.append(ExampleSection(title: "Advanced", items: advancedItems))

        results.append(
            ExampleSection(
                title: "Physically Based Rendering",
                items: [
                    ExampleItem(id: "pbr", title: "PBR Point Shadows", systemImage: "eye") { PBRRendererView() },
                    ExampleItem(id: "pbr-customization", title: "PBR Customization", systemImage: "gear") { PBRCustomizationRendererView() },
                    ExampleItem(id: "pbr-physical-material", title: "PBR Physical Point Shadows", systemImage: "party.popper") { PBREnhancedRendererView() },
                    ExampleItem(id: "pbr-standard-material", title: "PBR Standard Material", systemImage: "flame") { PBRStandardMaterialRendererView() },
                    ExampleItem(id: "pbr-submeshes", title: "PBR Submeshes", systemImage: "soccerball") { PBRSubmeshRendererView() }
                ]
            )
        )

        var postProcessingItems: [ExampleItem] = [
            ExampleItem(id: "post-processing", title: "Post Processing", systemImage: "checkerboard.rectangle") { PostProcessingRendererView() },
            ExampleItem(id: "bloom", title: "Bloom", systemImage: "sun.max.fill") { BloomRendererView() },
            ExampleItem(id: "fxaa", title: "FXAA", systemImage: "squareshape.split.2x2.dotted") { FXAARendererView() }
        ]
        #if os(macOS)
            postProcessingItems.append(
                ExampleItem(id: "screen-capture", title: "Screen Capture", systemImage: "display.and.arrow.down") {
                    ScreenCaptureRendererView()
                }
            )
        #endif
        results.append(ExampleSection(title: "Post Processing", items: postProcessingItems))

        return results
    }

    private var selectedItem: ExampleItem? {
        guard let selection else { return nil }
        return sections.flatMap(\.items).first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sections) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.items) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .tag(item.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Satin Examples")
        } detail: {
            if let selectedItem {
                selectedItem.makeView()
                    .id(selectedItem.id)
            } else {
                ContentUnavailableView("Select an Example", systemImage: "square.stack.3d.up")
            }
        }
    }
}

#if false
    #Preview {
        ContentView()
            .preferredColorScheme(.dark)
    }
#endif
