import Foundation
import Metal
import Satin
import XCTest

final class AttributeRefactorTests: XCTestCase {
    private struct InterleavedVertex {
        var position: simd_float3
        var texcoord: simd_float2
    }

    private func makeDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }

    private func makeContext() -> Context? {
        guard let device = makeDevice() else { return nil }
        return VisualTestHarness.makeContext(device: device)
    }

    func testGeometryMaintainsConcreteAttributeBuckets() throws {
        guard let context = makeContext() else { return }

        let geometry = Geometry(context: context)
        let pointer = UnsafeMutablePointer<InterleavedVertex>.allocate(capacity: 2)
        pointer.initialize(to: InterleavedVertex(position: [0, 0, 0], texcoord: [0, 0]))
        pointer.advanced(by: 1).initialize(to: InterleavedVertex(position: [1, 1, 0], texcoord: [1, 1]))
        defer {
            pointer.deinitialize(count: 2)
            pointer.deallocate()
        }

        let interleavedBuffer = InterleavedBuffer(
            index: .Vertices,
            data: UnsafeMutableRawPointer(pointer),
            stride: MemoryLayout<InterleavedVertex>.stride,
            count: 2,
            source: nil
        )
        let position = Float3InterleavedBufferAttribute(parent: interleavedBuffer, offset: 0)
        let texcoord = Float2InterleavedBufferAttribute(
            parent: interleavedBuffer,
            offset: MemoryLayout<InterleavedVertex>.offset(of: \.texcoord) ?? MemoryLayout<simd_float3>.stride
        )
        let normal = Float3BufferAttribute(defaultValue: .zero, data: [[0, 0, 1], [0, 0, 1]])

        geometry.addAttribute(position, for: .Position)
        geometry.addAttribute(texcoord, for: .Texcoord)
        geometry.addAttribute(normal, for: .Normal)
        geometry.update()

        XCTAssertTrue(geometry.getAttribute(.Position) === position)
        XCTAssertTrue(geometry.getAttribute(.Texcoord) === texcoord)
        XCTAssertTrue(geometry.getAttribute(.Normal) === normal)
        XCTAssertEqual(geometry.vertexCount, 2)
        XCTAssertEqual(geometry.vertexBuffers.count, 2)

        let descriptor = geometry.vertexDescriptor
        XCTAssertEqual(descriptor.attributes[VertexAttributeIndex.Position.rawValue].bufferIndex, VertexBufferIndex.Vertices.rawValue)
        XCTAssertEqual(descriptor.attributes[VertexAttributeIndex.Position.rawValue].offset, 0)
        XCTAssertEqual(descriptor.attributes[VertexAttributeIndex.Texcoord.rawValue].bufferIndex, VertexBufferIndex.Vertices.rawValue)
        XCTAssertEqual(descriptor.attributes[VertexAttributeIndex.Texcoord.rawValue].offset, MemoryLayout<InterleavedVertex>.offset(of: \.texcoord))
        XCTAssertEqual(descriptor.attributes[VertexAttributeIndex.Normal.rawValue].bufferIndex, VertexAttributeIndex.Normal.bufferIndex.rawValue)
        XCTAssertEqual(descriptor.layouts[VertexBufferIndex.Vertices.rawValue].stride, MemoryLayout<InterleavedVertex>.stride)

        geometry.removeAttribute(.Texcoord)
        XCTAssertNil(geometry.getAttribute(.Texcoord))
    }

    func testAnyBufferAttributeRoundTripsConcreteSubclass() throws {
        let attribute = AnyBufferAttribute(
            Float3BufferAttribute(defaultValue: .zero, data: [[1, 2, 3], [4, 5, 6]])
        )

        let encoded = try JSONEncoder().encode(attribute)
        let decoded = try JSONDecoder().decode(AnyBufferAttribute.self, from: encoded)

        let decodedAttribute = try XCTUnwrap(decoded.attribute as? Float3BufferAttribute)
        XCTAssertEqual(decoded.type, .float3)
        XCTAssertEqual(decodedAttribute.count, 2)
        XCTAssertEqual(decodedAttribute.data[0], simd_float3(1, 2, 3))
        XCTAssertEqual(decodedAttribute.data[1], simd_float3(4, 5, 6))
    }

    func testBasicDiffuseAmbientDefaultsToZeroAndCanBeSet() throws {
        guard let context = makeContext() else { return }

        let material = BasicDiffuseMaterial(context: context)
        XCTAssertEqual(material.ambient, 0.0)

        material.ambient = 0.18
        XCTAssertEqual(material.ambient, 0.18, accuracy: 0.0001)
    }

    func testOffscreenRenderPerfHarness() throws {
        let frameCounts = [100, 1000]
        for frames in frameCounts {
            let elapsed = try measureOffscreenRender(frames: frames)
            print("Satin offscreen perf: \(frames) frames in \(String(format: "%.3f", elapsed))s")
        }
    }

    private func measureOffscreenRender(frames: Int) throws -> TimeInterval {
        guard
            let device = makeDevice(),
            let commandQueue = device.makeCommandQueue()
        else {
            throw XCTSkip("Metal is unavailable on this machine.")
        }

        let context = VisualTestHarness.makeContext(device: device)
        let renderer = RenderEncoder(context: context, clearColor: VisualTestHarness.defaultClearColor)
        renderer.resize((width: 64, height: 64))

        let camera = PerspectiveCamera(context: context, position: [0, 0, 8], near: 0.1, far: 100.0, fov: 30.0)
        camera.aspect = 1.0
        camera.lookAt(target: .zero)

        let scene = Object(context: context, label: "Perf Scene")
        let sharedGeometry = SphereGeometry(context: context, radius: 0.16, angularResolution: 16, verticalResolution: 8)
        let sharedMaterial = BasicDiffuseMaterial(context: context, color: [0.92, 0.74, 0.24, 1.0], blending: .disabled, hardness: 0.65)
        let light = DirectionalLight(context: context, color: [1, 1, 1], intensity: 1.4)
        light.position = [0.5, 1.0, 0.5]
        scene.add(light)

        for y in 0 ..< 10 {
            for x in 0 ..< 10 {
                let mesh = Mesh(context: context, geometry: sharedGeometry, material: sharedMaterial.clone())
                mesh.position = [Float(x) * 0.4 - 1.8, Float(y) * 0.4 - 1.8, 0]
                scene.add(mesh)
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 64,
            height: 64,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "AttributeRefactorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output texture"])
        }

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< frames {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw NSError(domain: "AttributeRefactorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer"])
            }

            try renderer.draw(
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                camera: camera,
                renderTarget: outputTexture
            )

            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            if let error = commandBuffer.error {
                throw error
            }
        }

        return CFAbsoluteTimeGetCurrent() - start
    }
}
