//
//  ContentView.swift
//  Example
//
//  Created by Reza Ali on 8/12/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Metal
import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum ExampleSection: String, CaseIterable {
    #if os(visionOS)
    case vision = "Vision"
    #endif
    #if os(iOS)
    case ar = "AR"
    #endif
    case basics = "Basics"
    case text = "Text"
    case materials = "Materials"
    case geometry = "Geometry"
    case customization = "Customization"
    case compute = "Compute"
    case shadows = "Shadows"
    case advanced = "Advanced"
    case pbr = "Physically Based Rendering"
    case postProcessing = "Post Processing"
}

private enum ExampleRoute: String, Hashable, Identifiable {
    #if os(visionOS)
    case visions
    #endif

    #if os(iOS)
    case arHelloWorld
    case arContactShadow
    case arDrawing
    case arBloom
    case arLidarMesh
    case arPBR
    case arPeopleOcclusion
    case arPlanes
    case arPointCloud
    #endif

    case renderer2D
    case renderer3D
    case instancedMesh
    case cameraController
    case orbitCameraController

    case sdfText
    case textGeometry
    case extrudedText

    case skyboxMaterial
    case gridMaterial
    case matcapMaterial
    case depthMaterial
    case occlusionMaterial
    case liveMaterial

    case superShapes
    case objLoading
    case octasphere
    case uvDisk
    case exportGeometry

    case customGeometry
    case customInstancing
    case customVertexAttributes

    case bufferCompute
    case flockingParticles
    case textureCompute
    case waveSimulation
    case jumpFloodOutline

    case contactShadow
    case directionalShadow
    case projectedShadow

    #if os(macOS)
    case audioInput
    case rawMetalLayerA
    case rawMetalLayerB
    case satinClearA
    case satinClearB
    case minimalSatin2D
    #endif
    case meshShader
    case bufferGeometry
    case rayMarching
    case multipleContext
    case vertexAmplification
    case tessellation

    case pbr
    case pbrCustomization
    case pbrPhysicalMaterial
    case pbrStandardMaterial
    case pbrSubmeshes

    case postProcessing
    case bloom
    case fxaa
    #if os(macOS)
    case screenCapture
    #endif

    var id: Self { self }

    var title: String {
        switch self {
            #if os(visionOS)
            case .visions: "Immersive"
            #endif

            #if os(iOS)
            case .arHelloWorld: "AR Hello World"
            case .arContactShadow: "AR Contact Shadow"
            case .arDrawing: "AR Drawing"
            case .arBloom: "AR Bloom"
            case .arLidarMesh: "AR Lidar Mesh"
            case .arPBR: "AR PBR"
            case .arPeopleOcclusion: "AR People Occlusion"
            case .arPlanes: "AR Planes"
            case .arPointCloud: "AR Point Cloud"
            #endif

            case .renderer2D: "2D"
            case .renderer3D: "3D"
            case .instancedMesh: "Instanced Mesh"
            case .cameraController: "Camera Controller"
            case .orbitCameraController: "Orbit Camera Controller"

            case .sdfText: "SDF Text"
            case .textGeometry: "Text Geometry"
            case .extrudedText: "Extruded Text"

            case .skyboxMaterial: "Skybox Material"
            case .gridMaterial: "Grid Material"
            case .matcapMaterial: "Matcap Material"
            case .depthMaterial: "Depth Material"
            case .occlusionMaterial: "Occlusion Material"
            case .liveMaterial: "Live Material"

            case .superShapes: "Super Shapes"
            case .objLoading: "Obj Loading"
            case .octasphere: "Octasphere"
            case .uvDisk: "UV Disk"
            case .exportGeometry: "Export Geometry"

            case .customGeometry: "Custom Geometry"
            case .customInstancing: "Custom Instancing"
            case .customVertexAttributes: "Custom Vertex Attributes"

            case .bufferCompute: "Buffer Compute"
            case .flockingParticles: "Flocking Particles"
            case .textureCompute: "Texture Compute"
            case .waveSimulation: "Wave Simulation"
            case .jumpFloodOutline: "Jump Flood Outline"

            case .contactShadow: "Contact Shadow"
            case .directionalShadow: "Directional Shadow"
            case .projectedShadow: "Projected Shadow"

            #if os(macOS)
            case .audioInput: "Audio Input"
            case .rawMetalLayerA: "Raw Metal A"
            case .rawMetalLayerB: "Raw Metal B"
            case .satinClearA: "Satin Clear A"
            case .satinClearB: "Satin Clear B"
            case .minimalSatin2D: "Minimal Satin 2D"
            #endif
            case .meshShader: "Mesh Shader"
            case .bufferGeometry: "Buffer Geometry"
            case .rayMarching: "Ray Marching"
            case .multipleContext: "Multiple Context"
            case .vertexAmplification: "Vertex Amplification"
            case .tessellation: "Tessellation"

            case .pbr: "PBR"
            case .pbrCustomization: "PBR Customization"
            case .pbrPhysicalMaterial: "PBR Physical Material"
            case .pbrStandardMaterial: "PBR Standard Material"
            case .pbrSubmeshes: "PBR Submeshes"

            case .postProcessing: "Post Processing"
            case .bloom: "Bloom"
            case .fxaa: "FXAA"
            #if os(macOS)
            case .screenCapture: "Screen Capture"
            #endif
        }
    }

    var systemImage: String {
        switch self {
            #if os(visionOS)
            case .visions: "visionpro"
            #endif

            #if os(iOS)
            case .arHelloWorld: "arkit"
            case .arContactShadow: "square.2.layers.3d.bottom.filled"
            case .arDrawing: "scribble.variable"
            case .arBloom: "sun.max.circle"
            case .arLidarMesh: "point.3.filled.connected.trianglepath.dotted"
            case .arPBR: "party.popper"
            case .arPeopleOcclusion: "person.2.fill"
            case .arPlanes: "squareshape"
            case .arPointCloud: "cloud"
            #endif

            case .renderer2D: "square"
            case .renderer3D: "cube"
            case .instancedMesh: "circle.grid.2x2.fill"
            case .cameraController: "camera.aperture"
            case .orbitCameraController: "rotate.3d.circle"

            case .sdfText: "f.cursive"
            case .textGeometry: "textformat"
            case .extrudedText: "square.3.layers.3d.down.right"

            case .skyboxMaterial: "map"
            case .gridMaterial: "grid"
            case .matcapMaterial: "graduationcap"
            case .depthMaterial: "rectangle.stack"
            case .occlusionMaterial: "moonphase.first.quarter.inverse"
            case .liveMaterial: "doc.text"

            case .superShapes: "seal"
            case .objLoading: "arrow.down.doc"
            case .octasphere: "globe"
            case .uvDisk: "hexagon.fill"
            case .exportGeometry: "square.and.arrow.up"

            case .customGeometry: "network"
            case .customInstancing: "square.grid.3x3"
            case .customVertexAttributes: "asterisk.circle"

            case .bufferCompute: "aqi.medium"
            case .flockingParticles: "bird"
            case .textureCompute: "photo.stack"
            case .waveSimulation: "water.waves"
            case .jumpFloodOutline: "squareshape.split.3x3"

            case .contactShadow: "square.2.layers.3d.bottom.filled"
            case .directionalShadow: "shadow"
            case .projectedShadow: "shadow"

            #if os(macOS)
            case .audioInput: "mic"
            case .rawMetalLayerA: "square.stack.3d.up"
            case .rawMetalLayerB: "square.stack.3d.down.right"
            case .satinClearA: "square.fill"
            case .satinClearB: "square.lefthalf.filled"
            case .minimalSatin2D: "square.inset.filled"
            #endif
            case .meshShader: "circle.hexagongrid.fill"
            case .bufferGeometry: "camera.metering.multispot"
            case .rayMarching: "camera.metering.multispot"
            case .multipleContext: "rectangle.split.2x1"
            case .vertexAmplification: "rectangle.split.2x1"
            case .tessellation: "square.split.2x2"

            case .pbr: "eye"
            case .pbrCustomization: "gear"
            case .pbrPhysicalMaterial: "party.popper"
            case .pbrStandardMaterial: "flame"
            case .pbrSubmeshes: "soccerball"

            case .postProcessing: "checkerboard.rectangle"
            case .bloom: "sun.max.fill"
            case .fxaa: "squareshape.split.2x2.dotted"
            #if os(macOS)
            case .screenCapture: "display.and.arrow.down"
            #endif
        }
    }

    var section: ExampleSection {
        switch self {
            #if os(visionOS)
            case .visions:
                return .vision
            #endif

            #if os(iOS)
            case .arHelloWorld, .arContactShadow, .arDrawing, .arBloom, .arLidarMesh, .arPBR, .arPeopleOcclusion, .arPlanes, .arPointCloud:
                return .ar
            #endif

            case .renderer2D, .renderer3D, .instancedMesh, .cameraController, .orbitCameraController:
                return .basics
            case .sdfText, .textGeometry, .extrudedText:
                return .text
            case .skyboxMaterial, .gridMaterial, .matcapMaterial, .depthMaterial, .occlusionMaterial, .liveMaterial:
                return .materials
            case .superShapes, .objLoading, .octasphere, .uvDisk, .exportGeometry:
                return .geometry
            case .customGeometry, .customInstancing, .customVertexAttributes:
                return .customization
            case .bufferCompute, .flockingParticles, .textureCompute, .waveSimulation, .jumpFloodOutline:
                return .compute
            case .contactShadow, .directionalShadow, .projectedShadow:
                return .shadows
            #if os(macOS)
            case .audioInput, .rawMetalLayerA, .rawMetalLayerB, .satinClearA, .satinClearB, .minimalSatin2D, .meshShader, .bufferGeometry, .rayMarching, .multipleContext, .vertexAmplification, .tessellation:
                return .advanced
            #else
            case .meshShader, .bufferGeometry, .rayMarching, .multipleContext, .vertexAmplification, .tessellation:
                return .advanced
            #endif
            case .pbr, .pbrCustomization, .pbrPhysicalMaterial, .pbrStandardMaterial, .pbrSubmeshes:
                return .pbr
            #if os(macOS)
            case .screenCapture, .postProcessing, .bloom, .fxaa:
                return .postProcessing
            #else
            case .postProcessing, .bloom, .fxaa:
                return .postProcessing
            #endif
        }
    }

    var isAvailable: Bool {
        switch self {
            case .meshShader:
                guard let device = MTLCreateSystemDefaultDevice() else { return false }
                return device.supportsFamily(.mac2) || device.supportsFamily(.apple8)
            case .vertexAmplification, .tessellation:
                #if targetEnvironment(simulator)
                return false
                #else
                return true
                #endif
            default:
                return true
        }
    }

    static var available: [Self] {
        var examples: [Self] = []

        #if os(visionOS)
        examples.append(.visions)
        #endif

        #if os(iOS)
        examples += [
            .arHelloWorld,
            .arContactShadow,
            .arDrawing,
            .arBloom,
            .arLidarMesh,
            .arPBR,
            .arPeopleOcclusion,
            .arPlanes,
            .arPointCloud
        ]
        #endif

        examples += [
            .renderer2D,
            .renderer3D,
            .instancedMesh,
            .cameraController,
            .orbitCameraController,
            .sdfText,
            .textGeometry,
            .extrudedText,
            .skyboxMaterial,
            .gridMaterial,
            .matcapMaterial,
            .depthMaterial,
            .occlusionMaterial,
            .liveMaterial,
            .superShapes,
            .objLoading,
            .octasphere,
            .uvDisk,
            .exportGeometry,
            .customGeometry,
            .customInstancing,
            .customVertexAttributes,
            .bufferCompute,
            .flockingParticles,
            .textureCompute,
            .waveSimulation,
            .jumpFloodOutline,
            .contactShadow,
            .directionalShadow,
            .projectedShadow
        ]

        #if os(macOS)
        examples.append(.audioInput)
        examples.append(.rawMetalLayerA)
        examples.append(.rawMetalLayerB)
        examples.append(.satinClearA)
        examples.append(.satinClearB)
        examples.append(.minimalSatin2D)
        #endif

        examples += [
            .meshShader,
            .bufferGeometry,
            .rayMarching,
            .multipleContext,
            .vertexAmplification,
            .tessellation,
            .pbr,
            .pbrCustomization,
            .pbrPhysicalMaterial,
            .pbrStandardMaterial,
            .pbrSubmeshes,
            .postProcessing,
            .bloom,
            .fxaa
        ]

        #if os(macOS)
        examples.append(.screenCapture)
        #endif

        return examples.filter(\.isAvailable)
    }
}

struct ContentView: View {
    @State private var selection: ExampleRoute? = Self.defaultSelection

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ExampleSection.allCases, id: \.self) { section in
                    if !Self.examples(in: section).isEmpty {
                        Section(header: Text(section.rawValue)) {
                            ForEach(Self.examples(in: section), id: \.self) { example in
                                Label(example.title, systemImage: example.systemImage)
                                    .tag(example)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Satin Examples")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                }
            }
            #endif
        } detail: {
            if let selection {
                detailView(for: selection)
                    .id(selection)
            } else {
                ContentUnavailableView("Select an Example", systemImage: "square.stack.3d.up")
            }
        }
    }

    private static var defaultSelection: ExampleRoute? {
        #if os(macOS)
        .pbrStandardMaterial
        #else
        nil
        #endif
    }

    private static func examples(in section: ExampleSection) -> [ExampleRoute] {
        ExampleRoute.available.filter { $0.section == section }
    }

    @ViewBuilder
    private func detailView(for route: ExampleRoute) -> some View {
        switch route {
            #if os(visionOS)
            case .visions:
                VisionsView()
            #endif

            #if os(iOS)
            case .arHelloWorld:
                ARRendererView()
            case .arContactShadow:
                ARContactShadowRendererView()
            case .arDrawing:
                ARDrawingRendererView()
            case .arBloom:
                ARBloomRendererView()
            case .arLidarMesh:
                ARLidarMeshRendererView()
            case .arPBR:
                ARPBRRendererView()
            case .arPeopleOcclusion:
                ARPeopleOcclusionRendererView()
            case .arPlanes:
                ARPlanesRendererView()
            case .arPointCloud:
                ARPointCloudRendererView()
            #endif

            case .renderer2D:
                Renderer2DView()
            case .renderer3D:
                Renderer3DView()
            case .instancedMesh:
                InstancedMeshRendererView()
            case .cameraController:
                CameraControllerRendererView()
            case .orbitCameraController:
                OrbitCameraControllerRendererView()

            case .sdfText:
                SDFTextRendererView()
            case .textGeometry:
                TextRendererView()
            case .extrudedText:
                ExtrudedTextRendererView()

            case .skyboxMaterial:
                CubemapRendererView()
            case .gridMaterial:
                GridRendererView()
            case .matcapMaterial:
                MatcapRendererView()
            case .depthMaterial:
                DepthMaterialRendererView()
            case .occlusionMaterial:
                OcclusionRendererView()
            case .liveMaterial:
                LiveCodeRendererView()

            case .superShapes:
                SuperShapesRendererView()
            case .objLoading:
                LoadObjRendererView()
            case .octasphere:
                OctasphereRendererView()
            case .uvDisk:
                DiskRendererView()
            case .exportGeometry:
                ExportGeometryRendererView()

            case .customGeometry:
                CustomGeometryRendererView()
            case .customInstancing:
                CustomInstancingRendererView()
            case .customVertexAttributes:
                VertexAttributesRendererView()

            case .bufferCompute:
                BufferComputeRendererView()
            case .flockingParticles:
                FlockingRendererView()
            case .textureCompute:
                TextureComputeRendererView()
            case .waveSimulation:
                WaveSimulationRendererView()
            case .jumpFloodOutline:
                JumpFloodOutlineRendererView()

            case .contactShadow:
                ContactShadowRendererView()
            case .directionalShadow:
                DirectionalShadowRendererView()
            case .projectedShadow:
                ProjectedShadowRendererView()

            #if os(macOS)
            case .audioInput:
                AudioInputRendererView()
            case .rawMetalLayerA:
                RawMetalLayerAView()
            case .rawMetalLayerB:
                RawMetalLayerBView()
            case .satinClearA:
                SatinClearAView()
            case .satinClearB:
                SatinClearBView()
            case .minimalSatin2D:
                MinimalSatin2DRendererView()
            #endif
            case .meshShader:
                MeshShaderRendererView()
            case .bufferGeometry:
                BufferGeometryRendererView()
            case .rayMarching:
                RayMarchingRendererView()
            case .multipleContext:
                MultipleContextRendererView()
            case .vertexAmplification:
                MultipleViewportRendererView()
            case .tessellation:
                TessellationRendererView()

            case .pbr:
                PBRRendererView()
            case .pbrCustomization:
                PBRCustomizationRendererView()
            case .pbrPhysicalMaterial:
                PBREnhancedRendererView()
            case .pbrStandardMaterial:
                PBRStandardMaterialRendererView()
            case .pbrSubmeshes:
                PBRSubmeshRendererView()

            case .postProcessing:
                PostProcessingRendererView()
            case .bloom:
                BloomRendererView()
            case .fxaa:
                FXAARendererView()
            #if os(macOS)
            case .screenCapture:
                ScreenCaptureRendererView()
            #endif
        }
    }

    #if os(macOS)
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    #endif
}

#if false
    #Preview {
        ContentView()
            .preferredColorScheme(.dark)
    }
#endif
