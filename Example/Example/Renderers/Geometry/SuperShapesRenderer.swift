//
//  SuperShapesRenderer.swift
//  Example
//
//  Created by Reza Ali on 8/18/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Combine
import Metal
import MetalKit

import Forge
import Satin
import SatinCore

class SuperShapeGeometry: SatinGeometry {
    var r1: Float { didSet {
        if oldValue != r1 {
            _updateGeometryData = true
        }
    }}

    var a1: Float { didSet {
        if oldValue != a1 {
            _updateGeometryData = true
        }
    }}

    var b1: Float { didSet {
        if oldValue != b1 {
            _updateGeometryData = true
        }
    }}

    var m1: Float { didSet {
        if oldValue != m1 {
            _updateGeometryData = true
        }
    }}

    var n11: Float { didSet {
        if oldValue != n11 {
            _updateGeometryData = true
        }
    }}

    var n21: Float { didSet {
        if oldValue != n21 {
            _updateGeometryData = true
        }
    }}

    var n31: Float { didSet {
        if oldValue != n31 {
            _updateGeometryData = true
        }
    }}

    var r2: Float { didSet {
        if oldValue != r2 {
            _updateGeometryData = true
        }
    }}

    var a2: Float { didSet {
        if oldValue != a2 {
            _updateGeometryData = true
        }
    }}

    var b2: Float { didSet {
        if oldValue != b2 {
            _updateGeometryData = true
        }
    }}
    var m2: Float { didSet {
        if oldValue != m2 {
            _updateGeometryData = true
        }
    }}

    var n12: Float { didSet {
        if oldValue != n12 {
            _updateGeometryData = true
        }
    }}

    var n22: Float { didSet {
        if oldValue != n22 {
            _updateGeometryData = true
        }
    }}

    var n32: Float { didSet {
        if oldValue != n32 {
            _updateGeometryData = true
        }
    }}

    var res: Int { didSet {
        if oldValue != res {
            _updateGeometryData = true
        }
    }}

    init(r1: Float, a1: Float, b1: Float, m1: Float, n11: Float, n21: Float, n31: Float, r2: Float, a2: Float, b2: Float, m2: Float, n12: Float, n22: Float, n32: Float, res: Int) {
        self.r1 = r1
        self.a1 = a1
        self.b1 = b1
        self.m1 = m1
        self.n11 = n11
        self.n21 = n21
        self.n31 = n31
        self.r2 = r2
        self.a2 = a2
        self.b2 = b2
        self.m2 = m2
        self.n12 = n12
        self.n22 = n22
        self.n32 = n32
        self.res = res
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateSuperShapeGeometryData(r1, a1, b1, m1, n11, n21, n31, r2, a2, b2, m2, n12, n22, n32, Int32(res), Int32(res))
    }
}

class SuperShapesRenderer: BaseRenderer {
    var cancellables = Set<AnyCancellable>()

    var updateGeometry = true

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

    var parameters: ParameterGroup!

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

    lazy var mesh = Mesh(geometry: geometry, material: BasicDiffuseMaterial(0.7))

    lazy var camera: PerspectiveCamera = {
        let camera = PerspectiveCamera(position: simd_make_float3(2.0, 1.0, 4.0), near: 0.001, far: 200.0)
        camera.lookAt(target: .zero)
        return camera
    }()

    lazy var scene = Object("Scene", [mesh])
    lazy var context = Context(device, sampleCount, colorPixelFormat, depthPixelFormat, stencilPixelFormat)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: mtkView)
    lazy var renderer = Satin.Renderer(context: context)

    override func setupMtkView(_ metalKitView: MTKView) {
        metalKitView.isPaused = false
        metalKitView.sampleCount = 4
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.preferredFramesPerSecond = 60
    }

    override init() {
        super.init()
        setupParameters()
        setupObservers()
    }

    override func setup() {
        mesh.cullMode = .none
    }

    func setupParameters() {
        parameters = ParameterGroup("Shape Controls", [
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
    }

    func setupGeometry() {
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

    func setupObservers() {
        for param in parameters.params {
            if let p = param as? FloatParameter {
                p.$value.sink { [weak self] _ in
                    self?.updateGeometry = true
                }.store(in: &cancellables)
            } else if let p = param as? IntParameter {
                p.$value.sink { [weak self] _ in
                    self?.updateGeometry = true
                }.store(in: &cancellables)
            }
        }
    }

    override func update() {
        if updateGeometry {
            setupGeometry()
            updateGeometry = false
        }
        cameraController.update()
        camera.update()
        scene.update()
    }

    override func draw(_ view: MTKView, _ commandBuffer: MTLCommandBuffer) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(_ size: (width: Float, height: Float)) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
