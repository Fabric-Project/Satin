@testable import Satin
import Metal
import simd
import XCTest
#if SWIFT_PACKAGE
import SatinCore
#endif

/// Root and recorded casters obey the same conservative shadow reach tests.
final class RecordedShadowReachTests: XCTestCase {
    private var device: MTLDevice!
    private var context: Context!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                          depthPixelFormat: .depth32Float, stencilPixelFormat: .invalid)
    }

    private func makeTarget() throws -> MTLRenderPassDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        return pass
    }

    private func makeSubmission(_ renderer: RenderEncoder) -> SubmissionBuilder {
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 45)
        camera.aspect = 1
        return renderer.makeSubmissionBuilder(frame: .zero, cameras: [camera],
                                              viewports: [.init(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
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

    private func makeBox() -> Mesh {
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicDiffuseMaterial(context: context))
        mesh.scale = .init(repeating: 0.35)
        mesh.castShadow = true
        mesh.receiveShadow = true
        return mesh
    }

    /// Shadow encoder draw ranges, by reading SealedSubmission's private `passes` via Mirror.
    private func shadowDraws(_ sealed: SealedSubmission) -> (passes: Int, packets: Int) {
        var passCount = 0
        var packetCount = 0
        for child in Mirror(reflecting: sealed).children where child.label == "passes" {
            guard let passes = child.value as? [RecordedRenderPass] else { continue }
            for pass in passes where pass.label.contains("Shadow") {
                passCount += 1
                for command in pass.commands {
                    switch command {
                        case let .range(range, _): packetCount += range.count
                        case let .indices(indices, _): packetCount += indices.count
                        default: break
                    }
                }
            }
        }
        return (passCount, packetCount)
    }

    private func pointShadowDraws(casterRecorded: Bool, casterInReach: Bool, lightRecorded: Bool = false, frustumCulled: Bool = true) throws -> (passes: Int, packets: Int) {
        let renderer = RenderEncoder(context: context)
        renderer.resize((width: 64, height: 64))
        let light = PointLight(context: context, color: .one, radius: 2)
        light.position = [0, 0, 1]
        light.castShadow = true
        light.shadow.resolution = (64, 64)
        let receiver = makeReceiver()
        let near = makeBox()
        near.position = [0.5, 0, 0]
        let caster = makeBox()
        // Far outside the light's 2-unit reach, but along +x so the +x face's side planes contain it.
        caster.position = casterInReach ? [1, 0, 1] : [20, 0, 1]
        caster.frustumCulled = frustumCulled
        let root = Object(context: context, label: "Root", [receiver, near])
        if !lightRecorded { root.add(light) }
        let submission = makeSubmission(renderer)
        if lightRecorded {
            try submission.record(scene: Object(context: context, label: "Recorded Light", [light]))
        }
        if casterRecorded {
            caster.update()
            try submission.record(scene: Object(context: context, label: "Recorded", [caster]))
        } else {
            root.add(caster)
        }
        let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        try submission.record(scene: root, renderPassDescriptor: try makeTarget(), preparationCommandBuffer: commands)
        let sealed = try submission.seal()
        let counts = shadowDraws(sealed)
        try sealed.encode(into: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, String(describing: commands.error))
        return counts
    }

    func testRecordedCastersRespectPointLightReach() throws {
        for lightRecorded in [false, true] {
            let rootOut = try pointShadowDraws(casterRecorded: false, casterInReach: false, lightRecorded: lightRecorded)
            let recordedOut = try pointShadowDraws(casterRecorded: true, casterInReach: false, lightRecorded: lightRecorded)
            let rootIn = try pointShadowDraws(casterRecorded: false, casterInReach: true, lightRecorded: lightRecorded)
            let recordedIn = try pointShadowDraws(casterRecorded: true, casterInReach: true, lightRecorded: lightRecorded)
            XCTAssertEqual(rootOut.passes, 6)
            XCTAssertEqual(recordedOut.passes, 6)
            XCTAssertEqual(rootOut.packets, recordedOut.packets)
            XCTAssertEqual(rootIn.packets, recordedIn.packets)
            XCTAssertGreaterThan(rootIn.packets, rootOut.packets, "The in-reach caster must actually contribute draws")
            let uncullable = try pointShadowDraws(casterRecorded: true, casterInReach: false,
                                                 lightRecorded: lightRecorded, frustumCulled: false)
            XCTAssertGreaterThan(uncullable.packets, recordedOut.packets, "Opting out of culling preserves every pass")
        }
    }

    func testRecordedPointShadowKeepsItsCapturedReachAfterLightMoves() throws {
        let light = PointLight(context: context, color: .one, radius: 2)
        light.position = [0, 0, 1]
        light.castShadow = true
        light.shadow.resolution = (16, 16)
        light.updateViewIfNeeded()
        let captured = try RecordedShadow(light.shadow, context: context)
        let near = Bounds(min: [0.9, -0.1, 0.9], max: [1.1, 0.1, 1.1])
        let far = Bounds(min: [19.9, -0.1, 0.9], max: [20.1, 0.1, 1.1])
        XCTAssertTrue(captured.mayReach(near))
        XCTAssertFalse(captured.mayReach(far))
        light.position.x = 20
        light.updateViewIfNeeded()
        XCTAssertTrue(captured.mayReach(near))
        XCTAssertFalse(captured.mayReach(far))
        XCTAssertTrue(light.shadow.mayReach(far))
    }
}
