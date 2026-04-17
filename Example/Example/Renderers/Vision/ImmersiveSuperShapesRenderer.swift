//
//  ImmersiveSuperShapesRenderer.swift
//  Example
//
//  Created by Reza Ali on 1/23/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

#if os(visionOS)

import Combine
import CompositorServices
import Metal
import Satin

final class ImmersiveSuperShapesRenderer: ImmersiveBaseRenderer {
    final class GridMaterial: SourceMaterial {}

    lazy var background = Mesh(
        label: "Background",
        geometry: SkyboxGeometry(size: 200),
        material: GridMaterial(pipelinesURL: pipelinesURL, live: true)
    )

    var wireframe = false {
        didSet {
            mesh.triangleFillMode = wireframe ? .lines : .fill
        }
    }

    var r1Param = FloatParameter("R1", 1.0, 0, 2, .inputfield)
    var a1Param = FloatParameter("A1", 1.0, 0.0, 5.0, .slider)
    var b1Param = FloatParameter("B1", 1.0, 0.0, 5.0, .slider)
    var m1Param = FloatParameter("M1", 10, 0, 20, .slider)
    var n11Param = FloatParameter("N11", 1.087265, 0.0, 100.0, .slider)
    var n21Param = FloatParameter("N21", 0.938007, 0.0, 100.0, .slider)
    var n31Param = FloatParameter("N31", -0.615898, 0.0, 100.0, .slider)
    var r2Param = FloatParameter("R2", 0.984062, 0, 2, .slider)
    var a2Param = FloatParameter("A2", 1.513944, 0.0, 5.0, .slider)
    var b2Param = FloatParameter("B2", 0.642890, 0.0, 5.0, .slider)
    var m2Param = FloatParameter("M2", 5.225158, 0, 20, .slider)
    var n12Param = FloatParameter("N12", 1.0, 0.0, 100.0, .slider)
    var n22Param = FloatParameter("N22", 1.371561, 0.0, 100.0, .slider)
    var n32Param = FloatParameter("N32", 0.651718, 0.0, 100.0, .slider)
    var resParam = IntParameter("Resolution", 300, 3, 300, .slider)

    lazy var parameters: ParameterGroup = .init("Shape Controls", [
        resParam,
        r1Param,
        a1Param,
        b1Param,
        m1Param,
        n11Param,
        n21Param,
        n31Param,
        r2Param,
        a2Param,
        b2Param,
        m2Param,
        n12Param,
        n22Param,
        n32Param,
    ])

    var parametersSubscription: AnyCancellable?

    lazy var geometry = SuperShapeGeometry(
        r1: r1Param.value,
        a1: a1Param.value,
        b1: b1Param.value,
        m1: m1Param.value,
        n11: n11Param.value,
        n21: n21Param.value,
        n31: n31Param.value,
        r2: r2Param.value,
        a2: a2Param.value,
        b2: b2Param.value,
        m2: m2Param.value,
        n12: n12Param.value,
        n22: n22Param.value,
        n32: n32Param.value,
        res: resParam.value
    )

    lazy var startTime = getTime()
    lazy var mesh = Mesh(geometry: geometry, material: NormalColorMaterial(true))
    lazy var scene = Object(label: "Scene", [background, mesh])

    lazy var renderer = Renderer(context: defaultContext)

#if targetEnvironment(simulator)
    override var layerLayout: LayerRenderer.Layout { .dedicated }
#else
    override var layerLayout: LayerRenderer.Layout { .layered }
#endif

    override func setup() {
        mesh.position = [0, 1, -2]

        mesh.scale = .init(repeating: 0.25)
        mesh.cullMode = .none

        // parametersSubscription = parameters.objectWillChange.sink { [weak self] in
        //     self?.updateGeometry()
        // }
    }

    override func update() {
        mesh.orientation = simd_quatf(angle: Float(getTime() - startTime), axis: simd_normalize(simd_float3.one))
    }

    override func draw(
        frame: LayerRenderer.Frame,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        cameras: [PerspectiveCamera],
        viewports: [MTLViewport],
        viewMappings: [MTLVertexAmplificationViewMapping]
    ) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            cameras: cameras,
            viewports: viewports,
            viewMappings: viewMappings
        )
    }

    override func drawView(view: Int, frame: LayerRenderer.Frame, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, camera: PerspectiveCamera, viewport: MTLViewport) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            viewport: viewport
        )
    }

    private func updateGeometry() {
        geometry.r1 = r1Param.value
        geometry.a1 = a1Param.value
        geometry.b1 = b1Param.value
        geometry.m1 = m1Param.value
        geometry.n11 = n11Param.value
        geometry.n21 = n21Param.value
        geometry.n31 = n31Param.value
        geometry.r2 = r2Param.value
        geometry.a2 = a2Param.value
        geometry.b2 = b2Param.value
        geometry.m2 = m2Param.value
        geometry.n12 = n12Param.value
        geometry.n22 = n22Param.value
        geometry.n32 = n32Param.value
        geometry.res = resParam.value
    }
}

#endif
