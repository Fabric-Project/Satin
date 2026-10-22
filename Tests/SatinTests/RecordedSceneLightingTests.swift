@testable import Satin
import Metal
import simd
import XCTest

final class RecordedSceneLightingTests: XCTestCase {
    private var device: MTLDevice!
    private var context: Context!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                          depthPixelFormat: .depth32Float, stencilPixelFormat: .invalid)
    }

    func testRecordedCastersAndRootReceiverMatchOneStaticShadowedScene() throws {
        let recordedRoot = Object(context: context)
        recordedRoot.add(makeReceiver())
        recordedRoot.add(makeShadowLight())
        let material = BasicDiffuseMaterial(context: context)
        let mesh = makeBox(material: material)
        let iterated = Object(context: context, label: "Iterated", [mesh])
        let recorded = try render(root: recordedRoot) { submission in
            for (index, position) in [Float(-0.55), 0.55].enumerated() {
                mesh.position.x = position
                material.color = index == 0 ? [1, 0.2, 0.2, 1] : [0.2, 0.2, 1, 1]
                mesh.update()
                try submission.record(scene: iterated)
            }
        }

        let referenceRoot = Object(context: context)
        referenceRoot.add(makeReceiver())
        referenceRoot.add(makeShadowLight())
        for (index, position) in [Float(-0.55), 0.55].enumerated() {
            let material = BasicDiffuseMaterial(context: context, color: index == 0 ? [1, 0.2, 0.2, 1] : [0.2, 0.2, 1, 1])
            let mesh = makeBox(material: material)
            mesh.position.x = position
            referenceRoot.add(mesh)
        }
        let reference = try render(root: referenceRoot)
        XCTAssertEqual(recorded, reference)
        XCTAssertTrue(stride(from: 0, to: reference.count, by: 4).contains {
            reference[$0] != 0 || reference[$0 + 1] != 0 || reference[$0 + 2] != 0
        }, "The reference must draw visible lit surfaces")
    }

    func testLightsRecordedAfterAMeshIlluminateThatMeshAndTheRoot() throws {
        let material = BasicDiffuseMaterial(context: context)
        let recordedMesh = makeBox(material: material)
        recordedMesh.position.x = -0.55
        let meshScene = Object(context: context, label: "Recorded mesh", [recordedMesh])
        let rootMesh = makeBox(material: BasicDiffuseMaterial(context: context))
        rootMesh.position.x = 0.55
        let root = Object(context: context, label: "Root mesh", [rootMesh])
        let light = PointLight(context: context, color: [1, 0, 0], radius: 10)
        let lightScene = Object(context: context, label: "Recorded lights", [light])
        let recorded = try render(root: root) { submission in
            recordedMesh.update()
            try submission.record(scene: meshScene)
            light.position = [-1, 1, 3]
            try submission.record(scene: lightScene)
            light.position = [1, 1, 3]
            light.color = [0, 0, 1]
            try submission.record(scene: lightScene)
        }

        let reference = Object(context: context)
        for position in [Float(-0.55), 0.55] {
            let mesh = makeBox(material: BasicDiffuseMaterial(context: context))
            mesh.position.x = position
            reference.add(mesh)
        }
        for (position, color) in [(simd_float3(-1, 1, 3), simd_float3(1, 0, 0)),
                                  (simd_float3(1, 1, 3), simd_float3(0, 0, 1))] {
            let light = PointLight(context: context, color: color, radius: 10)
            light.position = position
            reference.add(light)
        }
        XCTAssertEqual(recorded, try render(root: reference))
    }

    func testRenderOrderAppliesAcrossRecordedAndRootObjects() throws {
        let red = BasicColorMaterial(context: context, color: [1, 0, 0, 1])
        red.depthCompareFunction = .always
        let blue = BasicColorMaterial(context: context, color: [0, 0, 1, 1])
        blue.depthCompareFunction = .always
        let recorded = makeBox(material: red)
        recorded.renderOrder = -10
        let root = makeBox(material: blue)
        root.renderOrder = 10
        let image = try render(root: Object(context: context, label: "Root", [root])) { submission in
            recorded.update()
            try submission.record(scene: Object(context: self.context, label: "Recorded", [recorded]))
        }
        let center = (32 * 64 + 32) * 4
        XCTAssertEqual(image[center], 255, "Higher renderOrder root blue draws after the recorded red")
        XCTAssertEqual(image[center + 2], 0)
    }

    private func makeBox(material: Material) -> Mesh {
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        mesh.scale = .init(repeating: 0.35)
        mesh.castShadow = true
        mesh.receiveShadow = true
        return mesh
    }

    private func makeReceiver() -> Mesh {
        let plane = PlaneGeometry(context: context)
        plane.width = 4
        plane.height = 4
        let mesh = Mesh(context: context, geometry: plane, material: BasicDiffuseMaterial(context: context))
        mesh.position.z = -0.75
        mesh.receiveShadow = true
        return mesh
    }

    private func makeShadowLight() -> DirectionalLight {
        let light = DirectionalLight(context: context, color: .one)
        light.position = [2, 3, 5]
        light.lookAt(target: .zero)
        light.castShadow = true
        light.shadow.resolution = (128, 128)
        light.shadow.radius = 0
        light.shadow.strength = 1
        return light
    }

    private func render(root: Object, records: ((SubmissionBuilder) throws -> Void)? = nil) throws -> [UInt8] {
        let renderer = RenderEncoder(context: context)
        renderer.sortObjects = true
        renderer.resize((width: 64, height: 64))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 45)
        camera.aspect = 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let submission = renderer.makeSubmissionBuilder(frame: .zero, cameras: [camera],
                                                        viewports: [.init(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
        try records?(submission)
        try submission.record(scene: root, renderPassDescriptor: pass, preparationCommandBuffer: commands)
        try submission.seal().encode(into: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, String(describing: commands.error))
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        bytes.withUnsafeMutableBytes { bytes in
            if let address = bytes.baseAddress {
                texture.getBytes(address, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
            }
        }
        return bytes
    }
}
