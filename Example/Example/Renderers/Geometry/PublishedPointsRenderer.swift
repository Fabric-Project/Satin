//
//  PublishedPointsRenderer.swift
//  Example
//

import Metal
import MetalKit
import Satin

/// Points a raw Metal compute pass writes every frame, drawn with a stock material. Each frame the
/// pass writes a new buffer from the context's allocator, publishes it as a `PublishedAttribute`
/// and hands it to the geometry with `setPoints`: it never writes a buffer it has already
/// published, so frames still in flight keep drawing the points they were recorded with.
final class PublishedPointsRenderer: BaseRenderer {
    let pointCount = 65536
    /// Generous enough for the kernel's breathing sphere, so the points are culled correctly
    /// without a CPU scan of positions the GPU wrote.
    let pointBounds = Bounds(min: [-1.3, -1.3, -1.3], max: [1.3, 1.3, 1.3])

    lazy var renderer = RenderEncoder(context: defaultContext)
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0, 0, 5], near: 0.01, far: 100.0, fov: 45)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)

    lazy var geometry = Geometry(context: defaultContext, primitiveType: .point)
    lazy var mesh = Mesh(context: defaultContext, geometry: geometry,
                         material: BasicPointMaterial(context: defaultContext, color: [0.4, 0.75, 1.0, 1.0], size: 2))
    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])

    var publishPipeline: MTLComputePipelineState?

    override func setup() throws {
        // CPU-published starting points, so the mesh has a position layout before the first pass.
        geometry.setPoints(try Points(positions: [.zero], allocator: defaultContext.gpuAllocator))

        let library = try device.makeLibrary(source: Self.kernelSource, options: nil)
        guard let function = library.makeFunction(name: "publishPositions") else { return }
        publishPipeline = try device.makeComputePipelineState(function: function)
    }

    override func update(frame: FrameTime) throws {
        try super.update(frame: frame)
        cameraController.update(frame: frame)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        if let publishPipeline {
            geometry.setPoints(try publishPositions(pipeline: publishPipeline, commandBuffer: commandBuffer))
        }

        try renderer.draw(
            frame: frameTime,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    /// Encodes this frame's positions into a new GPU-only buffer and publishes it.
    private func publishPositions(pipeline: MTLComputePipelineState, commandBuffer: MTLCommandBuffer) throws -> Points {
        let byteStride = MemoryLayout<simd_float4>.stride
        let buffer = try defaultContext.gpuAllocator.makeBuffer(length: byteStride * pointCount,
                                                                memoryClass: .gpuOnly,
                                                                label: "Published Positions")
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            var time = Float(frameTime.time)
            var count = UInt32(pointCount)
            encoder.label = "Publish Positions"
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.setBytes(&time, length: MemoryLayout<Float>.size, index: 1)
            encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)
            encoder.dispatchThreads(MTLSize(width: pointCount, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1))
            encoder.endEncoding()
        }

        // float3 positions padded to 16 bytes, as the kernel writes them.
        let position = PublishedAttribute(adopting: buffer,
                                          layout: AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: byteStride),
                                          count: pointCount)
        return Points(position: position, bounds: .known(pointBounds))
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }

    /// A breathing Fibonacci sphere: one point per thread.
    static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void publishPositions(device float4 *positions [[buffer(0)]],
                                 constant float &time [[buffer(1)]],
                                 constant uint &count [[buffer(2)]],
                                 uint id [[thread_position_in_grid]]) {
        if (id >= count) { return; }
        const float fraction = (float(id) + 0.5) / float(count);
        const float y = 1.0 - 2.0 * fraction;
        const float ring = sqrt(max(0.0, 1.0 - y * y));
        const float angle = float(id) * 2.39996323 + time * 0.3;
        const float radius = 1.0 + 0.25 * sin(time * 2.0 + y * 6.0);
        positions[id] = float4(cos(angle) * ring * radius, y * radius, sin(angle) * ring * radius, 1.0);
    }
    """
}
