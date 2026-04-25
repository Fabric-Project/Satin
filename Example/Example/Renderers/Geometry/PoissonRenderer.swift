//
//  PoissonRenderer.swift
//  Example
//
//  Created by Reza Ali on 11/9/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Foundation
import simd

import Metal
import MetalKit
import Satin

struct PoissonDiskSampler {
    let rect: Rectangle
    let width: Float
    let height: Float
    let minDistance: Float
    let k: Int // Number of candidates to try per active point

    private var grid: [Int32]
    private var activeList: [simd_float2] = []
    private var samples: [simd_float2] = []
    private let cellSize: Float
    private let gridWidth: Int32
    private let gridHeight: Int32

    init(rect: Rectangle, minDistance: Float, k: Int = 30) {
        self.rect = rect
        self.width = rect.width
        self.height = rect.height
        self.minDistance = minDistance
        self.k = k
        self.cellSize = minDistance / sqrt(2.0)
        self.gridWidth = Int32(ceil(width / cellSize))
        self.gridHeight = Int32(ceil(height / cellSize))

        self.grid = Array(repeating: -1, count: Int(gridWidth * gridHeight))
    }

    mutating func generateSamples() -> [SIMD2<Float>] {
        // Step 1: Place the first sample
//        let initialSample = SIMD2<Float>(x: Float.random(in: 0..<width), y: Float.random(in: 0..<height))
        let initialSample = simd_make_float2(
            Float.random(in: rect.min.x...rect.max.x),
            Float.random(in: rect.min.y...rect.max.y)
        )

        addSample(initialSample)

        let radius = minDistance
        let diameter = 2 * minDistance
        // Step 2: Process the active list
        while let activeSample = activeList.randomElement() {
            var found = false

            // Generate up to `k` candidates in the annulus around the active sample
            for _ in 0..<k {
                let angle = Float.random(in: 0..<2 * .pi)
                let distance = Float.random(in: radius..<diameter)
                let candidate = activeSample + distance * SIMD2<Float>(cos(angle), sin(angle))

                // Check if the candidate is within bounds and sufficiently far from existing samples
                if isValid(candidate) {
                    addSample(candidate)
                    found = true
                    break
                }
            }

            // Remove the active sample if no candidates were accepted
            if !found, let index = activeList.firstIndex(of: activeSample) {
                activeList.remove(at: index)
            }
        }

        return samples
    }

    // Helper to add a sample
    private mutating func addSample(_ sample: simd_float2) {
        samples.append(sample)
        activeList.append(sample)

        let gridPos = gridPosition(of: sample)
        setGridValue(gridPos, value: Int32(samples.count - 1))
    }

    private func getGridIndex(_ i: simd_int2) -> Int32 {
        i.y * gridWidth + i.x
    }

    private func getGridValue(_ i: simd_int2) -> Int32 {
        return grid[Int(getGridIndex(i))]
    }

    private mutating func setGridValue(_ i: simd_int2, value: Int32) {
        grid[Int(getGridIndex(i))] = value
    }

    // Check if a candidate is valid
    private func isValid(_ candidate: simd_float2) -> Bool {
        guard rect.contains(point: candidate) else { return false }

        let gridPos = gridPosition(of: candidate)

        // Check surrounding cells in the grid
        for i in max(0, gridPos.x - 2)...min(gridWidth - 1, gridPos.x + 2) {
            for j in max(0, gridPos.y - 2)...min(gridHeight - 1, gridPos.y + 2) {
                let index = getGridValue(simd_make_int2(i, j))
                if index > -1 {
                    let existingSample = samples[Int(index)]
                    if simd_distance(candidate, existingSample) < minDistance {
                        return false
                    }
                }
            }
        }

        return true
    }

    // Convert a position to grid coordinates
    private func gridPosition(of point: simd_float2) -> simd_int2 {
        simd_make_int2(
            Int32(remap(point.x, rect.min.x, rect.max.x, 0, Float(gridWidth))),
            Int32(remap(point.y, rect.min.y, rect.max.y, 0, Float(gridHeight)))
        )
    }
}

final class PoissonRenderer: BaseRenderer {
    var camera = OrthographicCamera()
    lazy var cameraController = OrthographicCameraController(camera: camera, view: metalView)
    lazy var scene = Object(label: "Scene", [intersectionMesh])
    lazy var renderer = Renderer(context: defaultContext)

    var intersectionMesh: Mesh = {
        let mesh = Mesh(geometry: CircleGeometry(radius: 10), material: BasicColorMaterial(color: [0.0, 1.0, 0.0, 1.0], blending: .disabled))
        mesh.label = "Intersection Mesh"
        mesh.renderPass = 1
        mesh.visible = false
        return mesh
    }()

    override func setup() {
        camera.near = 0.0
        camera.far = 40.96
        camera.position = [0, 0, 10.0]
//        camera.lookAt(target: .zero)
#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif

        generateSamplesViaCpp(color: [1, 0, 0, 1])
        generateSamplesViaSwift()
    }

    func generateSamplesViaSwift() {
        let rect = Rectangle(min: .init(-100, -100), max: .init(100, 100))
        // Usage
        let startTime = getTime()
        var sampler = PoissonDiskSampler(rect: rect, minDistance: 4, k: 30)
        let samples = sampler.generateSamples()
        let endTime = getTime()
        let deltaTime = (endTime - startTime) * 1000.0
        print("Swift Calculation Time: \(deltaTime) ms")

        var points = [simd_float3]()
        points.reserveCapacity(samples.count)

        for sample in samples {
            points.append(simd_make_float3(sample, 0.0))
        }

        let mesh = Mesh(
            label: "Points",
            geometry: PointGeometry(data: points),
            material: BasicPointMaterial(color: [0, 0, 1, 1], size: 8)
        )

        mesh.position.x += 100

        scene.add(mesh)
    }

    func generateSamplesViaCpp(color: simd_float4) {
        let rect = Rectangle(min: .init(-100, -100), max: .init(100, 100))
        // Usage
        let startTime = getTime()
        var points2D = generatePoissonDiskSamples(rect, 4, 30)
        let endTime = getTime()
        let deltaTime = (endTime - startTime) * 1000.0
        print("C++ Calculation Time: \(deltaTime) ms")

        var points = [simd_float3]()
        points.reserveCapacity(Int(points2D.count))

        for i in 0..<Int(points2D.count) {
            points.append(simd_make_float3(points2D.data[i], 0.0))
        }

        let mesh = Mesh(
            label: "Points",
            geometry: PointGeometry(data: points),
            material: BasicPointMaterial(color: color, size: 8)
        )

        scene.add(mesh)

        mesh.position.x -= 100

        freePoints2D(&points2D)
    }

    override func update() {
        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor _: Float) {
        cameraController.resize(size)
        renderer.resize(size)
    }

#if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let pt = normalizePoint(metalView.convert(event.locationInWindow, from: nil), metalView.frame.size)
        intersect(coordinate: pt)
    }

#elseif os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let first = touches.first {
            let point = first.location(in: metalView)
            let size = metalView.frame.size
            let pt = normalizePoint(point, size)
            intersect(coordinate: pt)
        }
    }
#endif

    func intersect(coordinate: simd_float2) {
        let results = raycast(camera: camera, coordinate: coordinate, object: scene)
        if let result = results.first {
            intersectionMesh.position = result.position
            intersectionMesh.visible = true
        }
    }

    func normalizePoint(_ point: CGPoint, _ size: CGSize) -> simd_float2 {
#if os(macOS)
        return 2.0 * simd_make_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1.0
#else
        return 2.0 * simd_make_float2(Float(point.x / size.width), 1.0 - Float(point.y / size.height)) - 1.0
#endif
    }
}
