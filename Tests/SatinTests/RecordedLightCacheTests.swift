import Metal
import simd
import XCTest
@testable import Satin

final class RecordedLightCacheTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                          depthPixelFormat: .depth32Float, stencilPixelFormat: .invalid)
    }

    func testRecordedLightIdentitiesUseRecordAndOccurrenceSlots() throws {
        let renderer = RenderEncoder(context: context)
        renderer.resize((width: 16, height: 16))
        let camera = PerspectiveCamera(context: context)
        let scene = Object(context: context, label: "Lights", [
            PointLight(context: context, color: [1, 0, 0]),
            PointLight(context: context, color: [0, 0, 1])
        ])
        func capture() throws -> [RecordedLightIdentity] {
            let builder = renderer.makeSubmissionBuilder(frame: .zero, cameras: [camera],
                viewports: [.init(originX: 0, originY: 0, width: 16, height: 16, znear: 0, zfar: 1)])
            try builder.record(scene: scene)
            try builder.record(scene: scene)
            return builder.lightOccurrences.map(\.identity)
        }
        let first = try autoreleasepool { try capture() }
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first[0].record, first[1].record)
        XCTAssertNotEqual(first[0].occurrenceIndex, first[1].occurrenceIndex,
                          "Two lights in one record must have different slots")
        XCTAssertNotEqual(first[0].record, first[2].record,
                          "The same light in another iteration must have a different record")
        let next = try autoreleasepool { try capture() }
        XCTAssertNotEqual(first[0].record.leaseToken, next[0].record.leaseToken,
                          "Returning and re-leasing packet storage must not reuse a light identity")
    }

    func testRecordedLightChangesAreUploadedAfterEarlierFramesAreReleased() throws {
        let renderer = RenderEncoder(context: context)
        renderer.resize((width: 16, height: 16))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 45)
        camera.aspect = 1
        let receiver = Mesh(context: context, geometry: BoxGeometry(context: context),
                            material: BasicDiffuseMaterial(context: context))
        let scene = Object(context: context, label: "Receiver", [receiver])
        let light = PointLight(context: context, color: [1, 0, 0], radius: 10)
        light.position = [0, 0, 3]
        let lightScene = Object(context: context, label: "Recorded light", [light])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 16, height: 16, mipmapped: false)
        descriptor.usage = .renderTarget
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let colors: [simd_float3] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [0, 1, 1], [1, 0, 1]]

        for frame in 0..<60 {
            try autoreleasepool {
                let expected = colors[frame % colors.count]
                light.color = expected
                light.radius = Float(10 + frame)
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
                let builder = renderer.makeSubmissionBuilder(frame: .zero, cameras: [camera],
                    viewports: [.init(originX: 0, originY: 0, width: 16, height: 16, znear: 0, zfar: 1)])
                try builder.record(scene: lightScene)
                try builder.record(scene: scene, renderPassDescriptor: pass, preparationCommandBuffer: commands)
                try builder.seal().encode(into: commands)
                commands.commit()
                commands.waitUntilCompleted()
                XCTAssertEqual(commands.status, .completed, String(describing: commands.error))
                let uploaded = try XCTUnwrap(renderer.uploadedLightData.first)
                XCTAssertEqual(simd_make_float3(uploaded.color), expected, "Frame \(frame)")
                XCTAssertEqual(uploaded.direction.w, light.data.direction.w,
                               "Captured radius must also invalidate the cache in frame \(frame)")
            }
        }
    }
}
