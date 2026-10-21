@testable import Satin
import Dispatch
import Foundation
import Metal
import simd
import XCTest

final class RenderQueueTests: XCTestCase {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private let size = 32

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    func testQueuedSceneKeepsItsRecordedValuesAfterProducerMutations() throws {
        let fixture = makeFixture()
        let reference = try target()
        let referenceBuffer = try commandBuffer()
        try draw(fixture, into: reference, using: referenceBuffer)
        try complete(referenceBuffer)

        let gate = SuspendedQueue(label: "Snapshot encoding")
        fixture.renderer.renderQueue = gate.queue
        let recorded = try target()
        let caller = try commandBuffer()
        try draw(fixture, into: recorded, using: caller)
        fixture.material.set("Color", simd_float4(0, 0, 1, 1))
        fixture.mesh.position = [100, 0, 0]
        fixture.mesh.geometry = SphereGeometry(context: fixture.renderer.context)
        fixture.scene.removeAll()
        fixture.camera.position = [20, 0, 5]
        gate.resume()
        try complete(caller)

        XCTAssertEqual(bytes(recorded), bytes(reference))
    }

    func testCallerReadbackRunsAfterQueuedRendering() throws {
        let fixture = makeFixture()
        let gate = SuspendedQueue(label: "Readback encoding")
        fixture.renderer.renderQueue = gate.queue
        let rendered = try target()
        let caller = try commandBuffer()
        try draw(fixture, into: rendered, using: caller)
        let readback = try XCTUnwrap(device.makeBuffer(length: size * size * 4, options: .storageModeShared))
        let blit = try XCTUnwrap(caller.makeBlitCommandEncoder())
        blit.copy(from: rendered, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: size, height: size, depth: 1), to: readback, destinationOffset: 0,
                  destinationBytesPerRow: size * 4, destinationBytesPerImage: size * size * 4)
        blit.endEncoding()
        gate.resume()
        try complete(caller)

        let centre = readback.contents().assumingMemoryBound(to: UInt8.self) + (size / 2 * size + size / 2) * 4
        XCTAssertEqual(Array(UnsafeBufferPointer(start: centre, count: 4)), [0, 0, 255, 255])
    }

    func testSharedAndSeparateEncodeQueuesPreserveGpuCallOrder() throws {
        for separateQueues in [false, true] {
            let first = makeFixture()
            let second = makeFixture(color: [0, 0, 1, 0.5], blending: .alpha)
            second.renderer.colorLoadAction = .load
            let reference = try target()
            let immediate = try commandBuffer()
            try draw(first, into: reference, using: immediate)
            try draw(second, into: reference, using: immediate)
            try complete(immediate)

            let gate = SuspendedQueue(label: "First encoding delayed")
            first.renderer.renderQueue = gate.queue
            let secondQueue = separateQueues ? DispatchQueue(label: "Second encoding can finish first") : gate.queue
            second.renderer.renderQueue = secondQueue
            let queued = try target()
            let caller = try commandBuffer()
            try draw(first, into: queued, using: caller)
            try draw(second, into: queued, using: caller)
            if separateQueues {
                let secondCommitted = expectation(description: "second CPU encode and commit finished first")
                secondQueue.async { secondCommitted.fulfill() }
                try awaitCompletion(secondCommitted)
            }
            gate.resume()
            try complete(caller)

            XCTAssertEqual(bytes(queued), bytes(reference))
        }
    }

    func testAdmissionBoundsOutstandingSubmissionsAtTwoAndThree() throws {
        for limit in [2, 3] {
            let fixture = makeFixture(limit: limit)
            // Warm the pipeline before timing the admission assertion.
            let warmup = try commandBuffer()
            try draw(fixture, into: target(), using: warmup)
            try complete(warmup)
            let gate = SuspendedQueue(label: "Admission \(limit)")
            fixture.renderer.renderQueue = gate.queue
            let caller = try commandBuffer()
            let rendered = try target()
            let initialCallsReturned = expectation(description: "\(limit) admitted calls returned")
            let producerFinished = expectation(description: "producer resumed")
            let extraReturned = DispatchSemaphore(value: 0)
            DispatchQueue(label: "Producer \(limit)").async {
                defer { producerFinished.fulfill() }
                do {
                    for _ in 0 ..< limit { try self.draw(fixture, into: rendered, using: caller) }
                    initialCallsReturned.fulfill()
                    try self.draw(fixture, into: rendered, using: caller)
                    extraReturned.signal()
                } catch { XCTFail("queued producer failed: \(error)") }
            }
            try awaitCompletion(initialCallsReturned)
            XCTAssertEqual(extraReturned.wait(timeout: .now() + .milliseconds(200)), .timedOut)
            gate.resume()
            try awaitCompletion(producerFinished)
            XCTAssertEqual(extraReturned.wait(timeout: .now() + .seconds(1)), .success)
            try complete(caller)
        }
    }

    func testRejectedDescriptorRestoresTargetAndReleasesAdmission() throws {
        let fixture = makeFixture(limit: 1)
        let gate = SuspendedQueue(label: "Failure recovery")
        fixture.renderer.renderQueue = gate.queue
        let caller = try commandBuffer()
        let valid = try target()
        let invalid = try target(format: .rgba32Float)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = valid
        let finished = expectation(description: "valid draw after rejection returned")
        DispatchQueue(label: "Failure producer").async {
            defer { finished.fulfill() }
            do {
                XCTAssertThrowsError(try fixture.renderer.draw(frame: .zero, renderPassDescriptor: descriptor,
                    commandBuffer: caller, scene: fixture.scene, camera: fixture.camera, renderTarget: invalid)) { error in
                    guard case .destinationMismatch = error as? SubmissionError else {
                        return XCTFail("unexpected rejection: \(error)")
                    }
                }
                XCTAssertTrue(descriptor.colorAttachments[0].texture === valid)
                try self.draw(fixture, into: valid, using: caller)
            } catch { XCTFail("permit was not usable after rejection: \(error)") }
        }
        try awaitCompletion(finished)
        gate.resume()
        try complete(caller)
        XCTAssertEqual(centrePixel(valid), [0, 0, 255, 255])
    }

    func testAlreadyEnqueuedCallerIsRejectedBeforeUpdatingTheScene() throws {
        let fixture = makeFixture(limit: 1)
        let gate = SuspendedQueue(label: "Rejected caller")
        fixture.renderer.renderQueue = gate.queue
        let caller = try commandBuffer()
        caller.enqueue()
        var updates = 0
        fixture.renderer.onUpdate = { updates += 1 }
        XCTAssertThrowsError(try draw(fixture, into: target(), using: caller)) { error in
            XCTAssertEqual(error as? SubmissionError, .commandBufferAlreadyEnqueued)
        }
        XCTAssertEqual(updates, 0)
        // A rejection must not leave a private buffer enqueued behind this caller.
        try complete(caller)
        fixture.renderer.onUpdate = nil
        let next = try commandBuffer()
        let rendered = try target()
        let returned = expectation(description: "rejection did not consume the only permit")
        DispatchQueue(label: "Caller rejection recovery").async {
            defer { returned.fulfill() }
            do { try self.draw(fixture, into: rendered, using: next) }
            catch { XCTFail("valid caller rejected: \(error)") }
        }
        try awaitCompletion(returned)
        gate.resume()
        try complete(next)
        XCTAssertEqual(centrePixel(rendered), [0, 0, 255, 255])
    }

    func testGpuPreparationUsesThePrivateBufferBeforeTheQueuedDraw() throws {
        let fixture = makeFixture()
        let gpuColor = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModePrivate))
        let red = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared))
        red.contents().storeBytes(of: simd_float4(1, 0, 0, 1), as: simd_float4.self)
        let blue = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared))
        blue.contents().storeBytes(of: simd_float4(0, 0, 1, 1), as: simd_float4.self)
        let initialize = try commandBuffer()
        let initializeBlit = try XCTUnwrap(initialize.makeBlitCommandEncoder())
        initializeBlit.copy(from: blue, sourceOffset: 0, to: gpuColor, destinationOffset: 0, size: 16)
        initializeBlit.endEncoding()
        try complete(initialize)

        let material = PreparedColorMaterial(context: fixture.renderer.context)
        material.gpuColor = gpuColor
        let mesh = PreparingMesh(context: fixture.renderer.context, geometry: BoxGeometry(context: fixture.renderer.context), material: material)
        mesh.upload = red
        mesh.destination = gpuColor
        let scene = Object(context: fixture.renderer.context, label: "GPU prepared", [mesh])
        let gate = SuspendedQueue(label: "Prepared encoding")
        fixture.renderer.renderQueue = gate.queue
        let caller = try commandBuffer()
        let rendered = try target()
        try fixture.renderer.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: caller,
                                  scene: scene, camera: fixture.camera, renderTarget: rendered)
        gate.resume()
        try complete(caller)
        XCTAssertEqual(centrePixel(rendered), [0, 0, 255, 255], "reading blue means preparation ran after the draw")
    }

    func testEncoderCanBeReleasedWhileItsWorkIsPending() throws {
        let gate = SuspendedQueue(label: "Released encoder")
        let rendered = try target()
        let caller = try commandBuffer()
        weak var released: RenderEncoder?
        let pool: PacketStoragePool = try autoreleasepool {
            let fixture = makeFixture()
            fixture.renderer.renderQueue = gate.queue
            released = fixture.renderer
            try draw(fixture, into: rendered, using: caller)
            return fixture.renderer.packetStoragePool
        }
        XCTAssertNil(released, "the queued closure must not capture its RenderEncoder")
        gate.resume()
        try complete(caller)
        XCTAssertEqual(centrePixel(rendered), [0, 0, 255, 255])
        // Completion handlers of separate command buffers need not finish in GPU order.
        let recycled = expectation(for: NSPredicate { _, _ in pool.availableCount == 1 }, evaluatedWith: nil)
        try awaitCompletion(recycled)
    }

    func testRecordedWorkUsesTheSameSchedulingAndCompletionPolicy() throws {
        let gate = SuspendedQueue(label: "Already encoded work")
        let admission = QueuedSubmission.Admission(limit: 1)
        let caller = try commandBuffer()
        let satinBuffer = try QueuedSubmission.begin(commandBuffer: caller, renderQueue: gate.queue, admission: admission)
        let output = try XCTUnwrap(device.makeBuffer(length: 4, options: .storageModeShared))
        output.contents().storeBytes(of: UInt32(0), as: UInt32.self)
        let commands = GPUCommandRecording(device: device)
        commands.append(FillBufferWork(buffer: output, range: 0 ..< 4, value: 47))
        QueuedSubmission.schedule(commands.seal(), satinBuffer: satinBuffer, renderQueue: gate.queue, admission: admission)
        XCTAssertEqual(output.contents().load(as: UInt32.self), 0, "no command encoded before the queue runs")
        XCTAssertEqual(satinBuffer.status, .enqueued)
        gate.resume()
        try complete(caller)
        XCTAssertEqual(output.contents().load(as: UInt32.self), 0x2F2F2F2F)
    }

    func testNilQueueStillEncodesIntoTheCallersBuffer() throws {
        let fixture = makeFixture()
        XCTAssertNil(fixture.renderer.renderQueue)
        let caller = try commandBuffer()
        let rendered = try target()
        try draw(fixture, into: rendered, using: caller)
        // A later caller-buffer clear must follow the draw in immediate mode.
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = rendered
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)
        try XCTUnwrap(caller.makeRenderCommandEncoder(descriptor: descriptor)).endEncoding()
        try complete(caller)
        XCTAssertEqual(centrePixel(rendered), [0, 255, 0, 255])
    }

    func testSixtyProducerMutationsRemainIsolatedDuringConcurrentEncoding() throws {
        let fixture = makeFixture()
        fixture.renderer.renderQueue = DispatchQueue(label: "Continuous scene encoding")
        let finished = expectation(description: "all recorded scenes completed")
        finished.expectedFulfillmentCount = 60
        for index in 0 ..< 60 {
            let isRed = index.isMultiple(of: 2)
            fixture.material.color = isRed ? [1, 0, 0, 1] : [0, 0, 1, 1]
            fixture.scene.removeAll()
            fixture.scene.add(fixture.mesh)
            let rendered = try target()
            let caller = try commandBuffer()
            try draw(fixture, into: rendered, using: caller)
            let expected: [UInt8] = isRed ? [0, 0, 255, 255] : [255, 0, 0, 255]
            caller.addCompletedHandler { completed in
                XCTAssertNil(completed.error)
                XCTAssertEqual(self.centrePixel(rendered), expected)
                finished.fulfill()
            }
            caller.commit()
        }
        try awaitCompletion(finished)
    }

    func testQueuedSceneEffectOverlayMatchesSynchronousOrder() throws {
        var results: [[UInt8]] = []
        for queued in [false, true] {
            let scene = makeFixture()
            let overlay = makeFixture()
            let source = try target()
            let filtered = try target()
            let output = try target()
            let context = effectContext()
            let effect = PostProcessEncoder(context: context,
                material: BasicTextureMaterial(context: context, texture: source))
            effect.resize(size: (Float(size), Float(size)), scaleFactor: 1)
            overlay.mesh.material = BasicTextureMaterial(context: overlay.renderer.context, texture: filtered)
            let gate = SuspendedQueue(label: "Scene effect overlay")
            if queued {
                scene.renderer.renderQueue = gate.queue
                effect.renderQueue = gate.queue
                overlay.renderer.renderQueue = gate.queue
            }
            let caller = try commandBuffer()
            try draw(scene, into: source, using: caller)
            try effect.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: caller, renderTarget: filtered)
            try draw(overlay, into: output, using: caller)
            gate.resume()
            try complete(caller)
            XCTAssertEqual(centrePixel(output), [0, 0, 255, 255])
            results.append(bytes(output))
        }
        XCTAssertEqual(results[0], results[1])
    }

    func testCompoundEffectUsesOneBufferAndRecoversItsPermitAfterFailure() throws {
        let fixture = makeFixture(limit: 1)
        let effect = CompoundEffect(context: effectContext(limit: fixture.renderer.context.maxBuffersInFlight))
        effect.resize(size: (Float(size), Float(size)), scaleFactor: 1)
        let gate = SuspendedQueue(label: "Compound effect")
        effect.renderQueue = gate.queue
        let caller = try commandBuffer()
        let rendered = try target()
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = rendered
        effect.shouldFail = true
        XCTAssertThrowsError(try effect.draw(frame: .zero, renderPassDescriptor: descriptor, commandBuffer: caller))
        effect.shouldFail = false
        let returned = expectation(description: "compound effect recovered admission")
        DispatchQueue(label: "Effect producer").async {
            defer { returned.fulfill() }
            do { try effect.draw(frame: .zero, renderPassDescriptor: descriptor, commandBuffer: caller) }
            catch { XCTFail("effect failed: \(error)") }
        }
        try awaitCompletion(returned)
        XCTAssertEqual(effect.bodyCalls, 2)
        gate.resume()
        try complete(caller)
        XCTAssertEqual(centrePixel(rendered), [0, 0, 255, 255])
    }

    func testQueuedMotionBlurIncludesFallbackDepthClear() throws {
        var results: [[UInt8]] = []
        for queued in [false, true] {
            let fixture = makeFixture()
            let source = try target()
            var sourceBytes = [UInt8](repeating: 0, count: size * size * 4)
            for pixel in 0 ..< size * size {
                sourceBytes[pixel * 4 + 2] = pixel % size < size / 2 ? 255 : 0
                sourceBytes[pixel * 4 + 3] = 255
            }
            source.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                           withBytes: sourceBytes, bytesPerRow: size * 4)
            let velocity = try target(format: .rgba32Float)
            var velocities = [Float](repeating: 0, count: size * size * 4)
            for pixel in 0 ..< size * size { velocities[pixel * 4] = 0.05 }
            velocity.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                             withBytes: velocities, bytesPerRow: size * 4 * MemoryLayout<Float>.size)
            let effect = MotionBlurPostProcessEncoder(context: fixture.renderer.context)
            effect.resize(size: (Float(size), Float(size)), scaleFactor: 1)
            effect.colorTexture = source
            effect.velocityTexture = velocity
            XCTAssertNil(effect.depthTexture) // Force the raw Metal clear inside the effect body.
            let gate = SuspendedQueue(label: "Motion blur depth clear")
            if queued { effect.renderQueue = gate.queue }
            let caller = try commandBuffer()
            let output = try target()
            try effect.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: caller, renderTarget: output)
            gate.resume()
            try complete(caller)
            results.append(bytes(output))
        }
        XCTAssertEqual(results[0], results[1])
        XCTAssertTrue(results[0].contains(255))
    }

    func testCompoundEffectsPreserveConfiguredAdmissionLimit() {
        let context = makeFixture(limit: 2).renderer.context
        XCTAssertEqual(MotionBlurPostProcessEncoder(context: context).context.maxBuffersInFlight, 2)
        XCTAssertEqual(SsaoPostProcessEncoder(context: context).context.maxBuffersInFlight, 2)
        XCTAssertEqual(SsgiPostProcessEncoder(context: context).context.maxBuffersInFlight, 2)
        XCTAssertEqual(BokehDepthOfFieldPostProcessEncoder(context: context).context.maxBuffersInFlight, 2)
    }

    func testEffectQueueTransitionsAtCommittedFrameBoundaries() throws {
        let context = effectContext()
        let material = BasicColorMaterial(context: context, color: [1, 0, 0, 1])
        let effect = PostProcessEncoder(context: context, material: material)
        effect.resize(size: (Float(size), Float(size)), scaleFactor: 1)
        let gate = SuspendedQueue(label: "Effect queue transitions")
        var outputs: [MTLTexture] = []
        for queued in [true, false, true] {
            effect.renderQueue = queued ? gate.queue : nil
            material.color = queued ? [1, 0, 0, 1] : [0, 0, 1, 1]
            let output = try target()
            outputs.append(output)
            let caller = try commandBuffer()
            try effect.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: caller, renderTarget: output)
            // This is the required boundary; earlier immediate work is committed before enqueue.
            caller.commit()
        }
        gate.resume()
        try complete(commandBuffer())
        XCTAssertEqual(centrePixel(outputs[0]), [0, 0, 255, 255])
        XCTAssertEqual(centrePixel(outputs[1]), [255, 0, 0, 255])
        XCTAssertEqual(centrePixel(outputs[2]), [0, 0, 255, 255])
    }

    func testEffectRejectsEnqueuedCallerBeforeEnteringBody() throws {
        let fixture = makeFixture(limit: 1)
        let effect = CompoundEffect(context: effectContext(limit: fixture.renderer.context.maxBuffersInFlight))
        effect.renderQueue = DispatchQueue(label: "Rejected effect caller")
        let caller = try commandBuffer()
        caller.enqueue()
        XCTAssertThrowsError(try effect.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: caller)) { error in
            XCTAssertEqual(error as? SubmissionError, .commandBufferAlreadyEnqueued)
        }
        XCTAssertEqual(effect.bodyCalls, 0)
        try complete(caller)
    }

    func testQueuedEffectCapturesComputeAndRenderWithoutRetainingItsOwner() throws {
        let library = try device.makeLibrary(source: """
            #include <metal_stdlib>
            using namespace metal;
            kernel void copyColor(constant float4 &color [[buffer(0)]], device float4 *output [[buffer(1)]]) {
                output[0] = color;
            }
            """, options: nil)
        let pipeline = try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "copyColor")))
        let gpuColor = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared))
        gpuColor.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 256)
        let gate = SuspendedQueue(label: "All effect encoding")
        let key = DispatchSpecificKey<Bool>()
        gate.queue.setSpecific(key: key, value: true)
        let encoded = DispatchSemaphore(value: 0)
        let caller = try commandBuffer()
        let output = try target()
        weak var released: ComputeEffect?
        try autoreleasepool {
            let context = effectContext()
            let material = PreparedColorMaterial(context: context)
            material.gpuColor = gpuColor
            let effect = ComputeEffect(context: context, material: material)
            released = effect
            effect.pipeline = pipeline
            effect.output = gpuColor
            effect.encodingObserver = { buffer in
                XCTAssertEqual(DispatchQueue.getSpecific(key: key), true)
                XCTAssertTrue(buffer.label?.hasSuffix("Queued Submission") == true)
                encoded.signal()
            }
            effect.renderQueue = gate.queue
            effect.resize(size: (Float(size), Float(size)), scaleFactor: 1)
            try effect.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: caller, renderTarget: output)
            effect.color = [0, 0, 1, 1]
            effect.mesh.position = [100, 0, 0]
            effect.mesh.material = BasicColorMaterial(context: context, color: [0, 0, 1, 1])
        }
        XCTAssertNil(released, "queued compute and rendering must not capture the effect")
        XCTAssertEqual(encoded.wait(timeout: .now()), .timedOut, "no custom Metal work ran on the producer")
        gate.resume()
        try complete(caller)
        XCTAssertEqual(encoded.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(centrePixel(output), [0, 0, 255, 255], "captured compute must precede the captured draw")
    }

    func testCustomWorkEncodesOnceOnTheQueueAndIsReleasedAfterCompletion() throws {
        let gate = SuspendedQueue(label: "Custom work")
        let caller = try commandBuffer()
        let admission = QueuedSubmission.Admission(limit: 1)
        let buffer = try QueuedSubmission.begin(commandBuffer: caller, renderQueue: gate.queue, admission: admission)
        let counter = EncodeCounter()
        weak var owner: LifetimeProbe?
        let recorded: RecordedGPUCommands = autoreleasepool {
            let workOwner = LifetimeProbe()
            owner = workOwner
            let commands = GPUCommandRecording(device: device)
            commands.append(CountingWork(counter: counter, owner: workOwner))
            return commands.seal()
        }
        QueuedSubmission.schedule(recorded, satinBuffer: buffer, renderQueue: gate.queue, admission: admission)
        XCTAssertEqual(counter.count, 0, "nothing is encoded on the producer")
        gate.resume()
        try complete(caller)
        XCTAssertEqual(counter.count, 1, "encoded exactly once")
        let released = expectation(for: NSPredicate { _, _ in owner == nil }, evaluatedWith: nil)
        try awaitCompletion(released)
        withExtendedLifetime(recorded) {}
    }

    func testAbandonedRecordingDropsCustomWorkWithoutEncodingIt() {
        let counter = EncodeCounter()
        weak var owner: LifetimeProbe?
        autoreleasepool {
            let workOwner = LifetimeProbe()
            owner = workOwner
            let commands = GPUCommandRecording(device: device)
            commands.append(CountingWork(counter: counter, owner: workOwner))
        }
        XCTAssertEqual(counter.count, 0)
        XCTAssertNil(owner, "an abandoned recording releases its work")
    }

    func testImmediateCustomWorkEncodesAtOnceAndHoldsItsValuesUntilCompletion() throws {
        let caller = try commandBuffer()
        let counter = EncodeCounter()
        weak var owner: LifetimeProbe?
        autoreleasepool {
            let workOwner = LifetimeProbe()
            owner = workOwner
            let commands = GPUCommandRecording(commandBuffer: caller)
            commands.append(CountingWork(counter: counter, owner: workOwner))
            commands.holdUntilCompleted(LifetimeProbe())
        }
        XCTAssertEqual(counter.count, 1, "immediate work encodes into the caller's buffer at once")
        XCTAssertNotNil(owner, "and stays alive until that buffer completes")
        try complete(caller)
        let released = expectation(for: NSPredicate { _, _ in owner == nil }, evaluatedWith: nil)
        try awaitCompletion(released)
    }

    func testRecordingHoldsExternalOwnersUntilCompletionButNotWhileKeptConsumed() throws {
        let gate = SuspendedQueue(label: "External resource owners")
        let caller = try commandBuffer()
        let admission = QueuedSubmission.Admission(limit: 1)
        let buffer = try QueuedSubmission.begin(commandBuffer: caller, renderQueue: gate.queue, admission: admission)
        weak var owner: LifetimeProbe?
        let recorded: RecordedGPUCommands = autoreleasepool {
            let resourceOwner = LifetimeProbe()
            owner = resourceOwner
            let commands = GPUCommandRecording(device: device)
            commands.holdUntilCompleted(resourceOwner)
            commands.append(ObservingWork { _ in XCTAssertNotNil(owner) })
            return commands.seal()
        }
        XCTAssertNotNil(owner)
        QueuedSubmission.schedule(recorded, satinBuffer: buffer, renderQueue: gate.queue, admission: admission)
        gate.resume()
        try complete(caller)
        let released = expectation(for: NSPredicate { _, _ in owner == nil }, evaluatedWith: nil)
        try awaitCompletion(released)
        withExtendedLifetime(recorded) {} // A consumed recording must not retain its commands forever.
    }

    private final class LifetimeProbe {}

    private final class ComputeEffect: PostProcessEncoder {
        var pipeline: MTLComputePipelineState?
        var output: MTLBuffer?
        var color: simd_float4 = [1, 0, 0, 1]
        var encodingObserver: ((MTLCommandBuffer) -> Void)?

        override func encodeEffect(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor,
            commands: GPUCommandRecording, viewports: [MTLViewport],
            viewMappings: [MTLVertexAmplificationViewMapping]) throws {
            let pipeline = try XCTUnwrap(pipeline)
            let output = try XCTUnwrap(output)
            var color = color
            if let encodingObserver { commands.append(ObservingWork(observe: encodingObserver)) }
            commands.compute(label: "Effect compute") { context in
                context.computeEncoder.setComputePipelineState(pipeline)
                context.computeEncoder.setBytes(&color, length: MemoryLayout<simd_float4>.stride, index: 0)
                context.computeEncoder.setBuffer(output, offset: 0, index: 1)
                context.computeEncoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            }
            try super.encodeEffect(frame: frame, renderPassDescriptor: renderPassDescriptor, commands: commands,
                                   viewports: viewports, viewMappings: viewMappings)
        }
    }

    private final class CompoundEffect: PostProcessEncoder {
        var shouldFail = false
        var bodyCalls = 0
        private lazy var child = PostProcessEncoder(context: context,
            material: BasicColorMaterial(context: context, color: [1, 0, 0, 1]))
        private enum Failure: Error { case deliberate }

        override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
            super.resize(size: size, scaleFactor: scaleFactor)
            child.resize(size: size, scaleFactor: scaleFactor)
        }

        override func encodeEffect(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor,
            commands: GPUCommandRecording, viewports: [MTLViewport],
            viewMappings: [MTLVertexAmplificationViewMapping]) throws {
            bodyCalls += 1
            let expectedLabel = label + " Queued Submission"
            commands.append(ObservingWork { buffer in XCTAssertEqual(buffer.label, expectedLabel) })
            XCTAssertNil(child.renderQueue)
            try commands.draw(child, frame: frame, renderPassDescriptor: renderPassDescriptor,
                              viewports: viewports, viewMappings: viewMappings)
            if shouldFail { throw Failure.deliberate }
        }
    }

    private func effectContext(limit: Int = 3) -> Context {
        Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, maxBuffersInFlight: limit)
    }

    private struct Fixture {
        let renderer: RenderEncoder
        let material: BasicColorMaterial
        let mesh: Mesh
        let scene: Object
        let camera: PerspectiveCamera
    }

    private func makeFixture(limit: Int = 3, color: simd_float4 = [1, 0, 0, 1], blending: Blending = .disabled) -> Fixture {
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                              depthPixelFormat: .depth32Float, maxBuffersInFlight: limit)
        let renderer = RenderEncoder(context: context)
        renderer.resize((Float(size), Float(size)))
        let material = BasicColorMaterial(context: context, color: color, blending: blending)
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: material)
        return Fixture(renderer: renderer, material: material, mesh: mesh,
                       scene: Object(context: context, label: "Queue test", [mesh]),
                       camera: PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30))
    }

    private func draw(_ fixture: Fixture, into target: MTLTexture, using commandBuffer: MTLCommandBuffer) throws {
        try fixture.renderer.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer,
                                  scene: fixture.scene, camera: fixture.camera, renderTarget: target)
    }

    private func target(format: MTLPixelFormat = .bgra8Unorm) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    private func commandBuffer() throws -> MTLCommandBuffer {
        try XCTUnwrap(commandQueue.makeCommandBuffer())
    }

    private func complete(_ commandBuffer: MTLCommandBuffer) throws {
        let completed = expectation(description: "GPU and completion handlers finished")
        commandBuffer.addCompletedHandler { _ in completed.fulfill() }
        commandBuffer.commit()
        try awaitCompletion(completed)
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)
    }

    private func awaitCompletion(_ expectation: XCTestExpectation) throws {
        guard XCTWaiter.wait(for: [expectation], timeout: 10) == .completed else {
            XCTFail("timed out: \(expectation.expectationDescription)")
            throw CompletionError.timedOut
        }
    }

    private func bytes(_ target: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size * size * 4)
        target.getBytes(&result, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return result
    }

    private func centrePixel(_ target: MTLTexture) -> [UInt8] {
        let start = (size / 2 * size + size / 2) * 4
        return Array(bytes(target)[start ..< start + 4])
    }

    private enum CompletionError: Error { case timedOut }

    private final class PreparingMesh: Mesh {
        var upload: MTLBuffer?
        var destination: MTLBuffer?

        override func encode(in context: EncodingContext) {
            super.encode(in: context)
            guard let upload, let destination else { return }
            context.commands.append(CopyBufferWork(source: upload, destination: destination, length: 16))
        }
    }

    private final class PreparedColorMaterial: BasicColorMaterial {
        override var prefix: String { "BasicColor" }
        var gpuColor: MTLBuffer?

        override func draw(in context: MaterialDrawContext) {
            super.draw(in: context)
            if let gpuColor { context.setFragmentBuffer(gpuColor, index: .MaterialUniforms) }
        }
    }

    /// Balances suspension even if a throwing assertion exits the test early.
    private final class SuspendedQueue {
        let queue: DispatchQueue
        private var suspended = true
        init(label: String) {
            queue = DispatchQueue(label: label)
            queue.suspend()
        }
        func resume() {
            guard suspended else { return }
            suspended = false
            queue.resume()
        }
        deinit { resume() }
    }
}

// MARK: - Custom GPU work fixtures: values and Metal resources only, as the contract requires.

/// Fills a range of a buffer.
struct FillBufferWork: RecordedGPUWork {
    let buffer: MTLBuffer
    let range: Range<Int>
    let value: UInt8

    func encode(into commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return XCTFail("missing blit encoder") }
        blit.fill(buffer: buffer, range: range, value: value)
        blit.endEncoding()
    }
}

/// Copies the first `length` bytes of one buffer into another.
struct CopyBufferWork: RecordedGPUWork {
    let source: MTLBuffer
    let destination: MTLBuffer
    let length: Int

    func encode(into commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return XCTFail("missing blit encoder") }
        blit.copy(from: source, sourceOffset: 0, to: destination, destinationOffset: 0, size: length)
        blit.endEncoding()
    }
}

/// Test-only: observes the command buffer it is encoded into.
struct ObservingWork: RecordedGPUWork {
    let observe: (MTLCommandBuffer) -> Void
    func encode(into commandBuffer: MTLCommandBuffer) { observe(commandBuffer) }
}

/// Test-only: observes the compute encoder it is encoded into.
struct ObservingComputeWork: RecordedComputeWork {
    let observe: (MTLComputeCommandEncoder) -> Void
    func encode(into computeEncoder: MTLComputeCommandEncoder) { observe(computeEncoder) }
}

/// Counts encodes. Read only after the command buffer completes.
final class EncodeCounter {
    var count = 0
}

/// Counts its encodes and holds an owner, to observe when the recording releases it.
struct CountingWork: RecordedGPUWork {
    let counter: EncodeCounter
    let owner: AnyObject

    func encode(into commandBuffer: MTLCommandBuffer) { counter.count += 1 }
}
