//
//  PolylineRenderer.swift
//  Example
//

import Metal
import MetalKit
import Satin

/// `PolylineGeometry` laid flat in the view plane (`up` is +z, toward the camera): three
/// zigzags showing each join with a different cap, an editable bezier path sampled and
/// simplified into a ribbon, and a moving trail rebuilt every frame that narrows toward its
/// oldest point. On macOS, drag the path's anchors and handles: an anchor carries its handles,
/// and a handle turns its partner too, so the path stays smooth.
final class PolylineRenderer: BaseRenderer {
    lazy var renderer = RenderEncoder(context: defaultContext)
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0, 0, 12], near: 0.1, far: 100.0, fov: 45)
    lazy var scene = Object(context: defaultContext, label: "Scene")

    /// Sharp and shallow turns, so each join shows its miter, bevel or fan.
    let zigzag: ContiguousArray<simd_float3> = [[-4, 0, 0], [-2.5, 0.8, 0], [-1, -0.6, 0], [0.2, 0.7, 0], [0.6, -0.5, 0], [2.4, 0.2, 0], [4, 0, 0]]
    let rows: [(join: PolylineJoinStyle, cap: PolylineCapStyle, y: Float, color: simd_float4)] = [
        (.miter, .butt, 3.6, [0.95, 0.45, 0.3, 1]),
        (.bevel, .square, 2.0, [0.35, 0.8, 0.45, 1]),
        (.round, .round, 0.4, [0.35, 0.6, 0.95, 1])
    ]

    lazy var trail = PolylineGeometry(context: defaultContext)
    var trailPoints: ContiguousArray<simd_float3> = []
    let trailLength = 90
    /// Oldest point thinnest: one width scale per trail point, from 0.1 up to 1.
    lazy var trailWidthScales = ContiguousArray((0 ..< trailLength).map { 0.1 + 0.9 * Float($0) / Float(trailLength - 1) })
    let trailStyle = PolylineStyle(width: 0.3, join: .round, cap: .round)
    lazy var startTime = getTime()

    // The editable path: a closed smooth spline through `anchors`. Segment i runs from anchor i
    // to anchor i + 1, leaving along `outHandles[i]` and arriving along `inHandles[i + 1]`.
    var anchors: [simd_float3] = [[4, -1.6, 0], [0, -0.6, 0], [-4, -1.6, 0], [0, -2.6, 0]]
    var outHandles: [simd_float3] = [[4, -1.1, 0], [-2.2, -0.6, 0], [-4, -2.1, 0], [2.2, -2.6, 0]]
    var inHandles: [simd_float3] = [[4, -2.1, 0], [2.2, -0.6, 0], [-4, -1.1, 0], [-2.2, -2.6, 0]]
    let pathStyle = PolylineStyle(width: 0.12, join: .round)
    lazy var pathGeometry = PolylineGeometry(context: defaultContext)
    lazy var pathMesh = Mesh(context: defaultContext, geometry: pathGeometry, material: BasicColorMaterial(context: defaultContext, color: [0.85, 0.5, 0.95, 1]))

    enum PathHandle {
        case anchor(Int)
        case inHandle(Int)
        case outHandle(Int)
    }
    /// One sphere per anchor and handle, and one line per anchor through its two handles.
    var handleMeshes: [(mesh: Mesh, handle: PathHandle)] = []
    var handleLines: [PolylineGeometry] = []
    var draggedHandle: PathHandle?
    /// Handles sit just in front of the ribbons so they draw over them and are hit first.
    let handleLift: simd_float3 = [0, 0, 0.05]

    override var sampleCount: Int {
#if targetEnvironment(simulator)
        1
#else
        4
#endif
    }

    override func setup() throws {
        for row in rows {
            let geometry = PolylineGeometry(context: defaultContext)
            geometry.update(points: ContiguousArray(zigzag.map { $0 + [0, row.y, 0] }), closed: false,
                            style: PolylineStyle(width: 0.35, join: row.join, cap: row.cap, roundResolution: 12))
            let mesh = Mesh(context: defaultContext, geometry: geometry, material: BasicColorMaterial(context: defaultContext, color: row.color))
            mesh.label = "\(row.join) join, \(row.cap) cap"
            mesh.cullMode = .none
            scene.add(mesh)
        }

        pathMesh.cullMode = .none
        scene.add(pathMesh)
        let anchorMaterial = BasicColorMaterial(context: defaultContext, color: [1, 1, 1, 1])
        let handleMaterial = BasicColorMaterial(context: defaultContext, color: [0.6, 0.6, 0.6, 1])
        // Lines and spheres have different vertex layouts, so they cannot share a material on this
        // branch: a material compiles one pipeline, for the layout of the mesh set up last.
        let handleLineMaterial = BasicColorMaterial(context: defaultContext, color: [0.6, 0.6, 0.6, 1])
        for anchorIndex in anchors.indices {
            let line = PolylineGeometry(context: defaultContext)
            let lineMesh = Mesh(context: defaultContext, geometry: line, material: handleLineMaterial)
            lineMesh.cullMode = .none
            scene.add(lineMesh)
            handleLines.append(line)
            for handle in [PathHandle.anchor(anchorIndex), .inHandle(anchorIndex), .outHandle(anchorIndex)] {
                let isAnchor = if case .anchor = handle { true } else { false }
                let mesh = Mesh(context: defaultContext, geometry: IcoSphereGeometry(context: defaultContext, radius: isAnchor ? 0.12 : 0.09, resolution: 2),
                                material: isAnchor ? anchorMaterial : handleMaterial)
                scene.add(mesh)
                handleMeshes.append((mesh, handle))
            }
        }
        rebuildPath()

        let trailMesh = Mesh(context: defaultContext, geometry: trail, material: BasicColorMaterial(context: defaultContext, color: [0.95, 0.85, 0.35, 1]))
        trailMesh.label = "Trail"
        trailMesh.cullMode = .none
//        trailMesh.triangleFillMode = .lines
        scene.add(trailMesh)

        camera.lookAt(target: .zero)
    }

    override func update() throws {
        // One new point a frame on a Lissajous curve, oldest dropped.
        let time = Float(getTime() - startTime)
        trailPoints.append([4 * sin(1.3 * time), -3.8 + 0.9 * sin(2.1 * time), 0])
        if trailPoints.count > trailLength { trailPoints.removeFirst(trailPoints.count - trailLength) }
        // While the trail is still filling, its points take the newest (widest) scales.
        trail.update(points: trailPoints, closed: false, style: trailStyle,
                     widthScales: ContiguousArray(trailWidthScales.suffix(trailPoints.count)))
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    // MARK: - Editable Path

    /// Builds the bezier path from the anchors and handles, samples and simplifies it into the
    /// ribbon, and moves the handle spheres and lines to match.
    func rebuildPath() {
        var path = BezierPath(start: anchors[0], isClosed: true)
        for anchorIndex in anchors.indices {
            let nextIndex = (anchorIndex + 1) % anchors.count
            path.addCubic(control1: outHandles[anchorIndex], control2: inHandles[nextIndex], to: anchors[nextIndex])
        }
        // Adaptive sampling puts points where the path turns; Ramer-Douglas-Peucker then drops
        // the ones that change its shape by less than the tolerance.
        let pathPoints = simplifyPolyline(path.sampledPoints(angleLimit: .pi / 90), tolerance: 0.005, closed: true)
        pathGeometry.update(points: pathPoints, closed: true, style: pathStyle)
        pathMesh.label = "Bezier path, \(pathPoints.count) points"

        for (mesh, handle) in handleMeshes {
            mesh.position = position(of: handle) + handleLift
        }
        for (anchorIndex, line) in handleLines.enumerated() {
            line.update(points: [inHandles[anchorIndex], anchors[anchorIndex], outHandles[anchorIndex]], closed: false,
                        style: PolylineStyle(width: 0.025))
        }
    }

    func position(of handle: PathHandle) -> simd_float3 {
        switch handle {
        case let .anchor(anchorIndex): anchors[anchorIndex]
        case let .inHandle(anchorIndex): inHandles[anchorIndex]
        case let .outHandle(anchorIndex): outHandles[anchorIndex]
        }
    }

    /// Moves `handle` to `point`. An anchor carries both its handles; a handle turns its partner
    /// to point the opposite way, keeping the partner's length, so the path stays smooth.
    func move(_ handle: PathHandle, to point: simd_float3) {
        switch handle {
        case let .anchor(anchorIndex):
            let delta = point - anchors[anchorIndex]
            anchors[anchorIndex] += delta
            inHandles[anchorIndex] += delta
            outHandles[anchorIndex] += delta
        case let .inHandle(anchorIndex):
            inHandles[anchorIndex] = point
            outHandles[anchorIndex] = mirrored(point, around: anchors[anchorIndex], keepingLengthOf: outHandles[anchorIndex])
        case let .outHandle(anchorIndex):
            outHandles[anchorIndex] = point
            inHandles[anchorIndex] = mirrored(point, around: anchors[anchorIndex], keepingLengthOf: inHandles[anchorIndex])
        }
        rebuildPath()
    }

    func mirrored(_ point: simd_float3, around anchor: simd_float3, keepingLengthOf partner: simd_float3) -> simd_float3 {
        let offset = point - anchor
        guard simd_length_squared(offset) > 0 else { return partner }
        return anchor - simd_normalize(offset) * simd_distance(partner, anchor)
    }

#if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let coordinate = normalizedCoordinate(of: event)
        let hit = raycast(camera: camera, coordinate: coordinate, objects: handleMeshes.map { $0.mesh }).first
        draggedHandle = handleMeshes.first { $0.mesh === hit?.object }?.handle
    }

    override func mouseDragged(with event: NSEvent) {
        guard let draggedHandle else { return }
        // Where the mouse ray meets the plane the path lies in (z = 0).
        let ray = Ray(camera: camera, coordinate: normalizedCoordinate(of: event))
        guard abs(ray.direction.z) > 1e-6 else { return }
        move(draggedHandle, to: ray.at(-ray.origin.z / ray.direction.z))
    }

    override func mouseUp(with event: NSEvent) {
        draggedHandle = nil
    }

    func normalizedCoordinate(of event: NSEvent) -> simd_float2 {
        let point = metalView.convert(event.locationInWindow, from: nil)
        let size = metalView.frame.size
        return 2 * simd_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1
    }
#endif

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
