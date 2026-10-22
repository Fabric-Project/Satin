@testable import Satin
import Foundation
import Metal
import XCTest

/// Uses real kernels and deliberately delays commit: rewriting every source ring slot must not
/// alter a compute dispatch's inputs. An Iterator updates one processor many times inside one
/// command buffer, so its dispatches outnumber the ring's slots.
final class ComputeInputSnapshotTests: XCTestCase {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    func testRegisteredStructInputsSurviveRingWrapOnBothSidesOfFourKilobytes() throws {
        for kind in BindingOwner.Kind.allCases {
            for length in [4, 4096, 4097] {
                let fixture = try makeFixture(kind: kind, inputIndex: .Custom0, length: length)
                let input = StructBuffer<UInt8>(device: device, count: length)
                var bytes = [UInt8](repeating: 7, count: length)
                bytes[length - 1] = 17
                input.update(data: bytes)
                fixture.owner.set(input, index: .Custom0)

                let encoded = try encode(fixture)
                for _ in 0 ..< Satin.maxBuffersInFlight {
                    input.update(data: [UInt8](repeating: 99, count: length))
                }

                try complete(encoded.commandBuffer)
                XCTAssertEqual(read(encoded.output), [7, 17], "\(kind), \(length) bytes")
            }
        }
    }

    func testRegisteredUniformInputsSurviveRingWrapAtSmallAndLargeSizes() throws {
        for kind in BindingOwner.Kind.allCases {
            for parameterCount in [1, 1025] {
                let parameters = makeParameters(count: parameterCount)
                let input = UniformBuffer(device: device, parameters: parameters)
                let fixture = try makeFixture(kind: kind, inputIndex: .Custom0, length: parameters.size, lastByte: 3)
                fixture.owner.set(input, index: .Custom0)

                let encoded = try encode(fixture)
                try XCTUnwrap(parameters.get("Amount", as: FloatParameter.self)).value = 9
                for _ in 0 ..< input.maxBuffersInFlight { input.update() }

                try complete(encoded.commandBuffer)
                // Float(1)'s uploaded representation: its low byte is 0 and high byte is 63.
                XCTAssertEqual(read(encoded.output), [0, 63], "\(kind), \(parameters.size) bytes")
            }
        }
    }

    func testRegisteredUniformCopiesUseTheUploadedSlotRatherThanNewParameterValues() throws {
        for kind in BindingOwner.Kind.allCases {
            for parameterCount in [1, 1025] {
                let parameters = makeParameters(count: parameterCount)
                let input = UniformBuffer(device: device, parameters: parameters)
                let fixture = try makeFixture(kind: kind, inputIndex: .Custom0, length: parameters.size, lastByte: 3)
                fixture.owner.set(input, index: .Custom0)
                try XCTUnwrap(parameters.get("Amount", as: FloatParameter.self)).value = 2

                let encoded = try encode(fixture)
                try complete(encoded.commandBuffer)
                XCTAssertEqual(read(encoded.output), [0, 63], "parameter edits alone must not upload, \(kind)")
            }
        }
    }

    func testProcessorOwnedUniformInputsSurviveRingWrapAtSmallAndLargeSizes() throws {
        for kind in BindingOwner.Kind.allCases {
            for parameterCount in [1, 1025] {
                let parameters = makeParameters(count: parameterCount)
                let fixture = try makeFixture(kind: kind, inputIndex: .Uniforms, length: parameters.size, lastByte: 3)
                let input = try fixture.owner.installUniforms(parameters)

                let encoded = try encode(fixture)
                try XCTUnwrap(parameters.get("Amount", as: FloatParameter.self)).value = 9
                for _ in 0 ..< input.maxBuffersInFlight { input.update() }

                try complete(encoded.commandBuffer)
                XCTAssertEqual(read(encoded.output), [0, 63], "\(kind), automatic uniforms")
            }
        }
    }

    func testPlainBuffersKeepTheirExplicitRetainedContentsContract() throws {
        for kind in BindingOwner.Kind.allCases {
            let fixture = try makeFixture(kind: kind, inputIndex: .Custom0, length: 4)
            let input = try XCTUnwrap(device.makeBuffer(length: 4, options: .storageModeShared))
            input.contents().initializeMemory(as: UInt8.self, repeating: 7, count: 4)
            fixture.owner.set(input, index: .Custom0)
            let encoded = try encode(fixture)
            input.contents().initializeMemory(as: UInt8.self, repeating: 19, count: 4)

            try complete(encoded.commandBuffer)
            XCTAssertEqual(read(encoded.output), [19, 19], "raw buffers must not silently become snapshots")
        }
    }

    func testRepeatedBindingsInOneEncoderKeepEachDispatchsOwnInput() throws {
        for kind in BindingOwner.Kind.allCases {
            for length in [4, 4097] {
                let fixture = try makeFixture(kind: kind, inputIndex: .Custom0, length: length)
                let input = StructBuffer<UInt8>(device: device, count: length)
                fixture.owner.set(input, index: .Custom0)
                let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
                let encoder = try XCTUnwrap(commandBuffer.makeComputeCommandEncoder())
                encoder.setComputePipelineState(fixture.pipeline)
                var outputs: [MTLBuffer] = []

                // Five updates wrap the current three-slot ring. Rebinding must capture each
                // dispatch's bytes, not leave all dispatches looking at the last ring contents.
                for value in [UInt8(3), 5, 7, 11, 13] {
                    input.update(data: [UInt8](repeating: value, count: length))
                    let output = try XCTUnwrap(device.makeBuffer(length: 8, options: .storageModeShared))
                    fixture.owner.set(output, index: .Custom1)
                    fixture.owner.bind(encoder: encoder, commandBuffer: commandBuffer)
                    encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                    outputs.append(output)
                }
                encoder.endEncoding()
                try complete(commandBuffer)

                for (output, expected) in zip(outputs, [UInt32(3), 5, 7, 11, 13]) {
                    XCTAssertEqual(read(output), [expected, expected], "\(kind), \(length) bytes")
                }
            }
        }
    }

    func testLargeSnapshotsOutliveTheirProcessorOnAnUnretainedCommandBuffer() throws {
        for kind in BindingOwner.Kind.allCases {
            let descriptor = MTLCommandBufferDescriptor()
            descriptor.retainedReferences = false
            let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer(descriptor: descriptor))
            let input = StructBuffer<UInt8>(device: device, count: 4097)
            input.update(data: [UInt8](repeating: 23, count: 4097))
            let encoded: (output: MTLBuffer, pipeline: MTLComputePipelineState) = try autoreleasepool {
                let fixture = try makeFixture(kind: kind, inputIndex: .Custom0, length: 4097)
                fixture.owner.set(input, index: .Custom0)
                return (try encode(fixture, commandBuffer: commandBuffer).output, fixture.pipeline)
            }
            // The fixture, processor and its arena owner are gone; only completion holds may
            // keep its snapshot alive. The unretained command buffer cannot hide a missing hold.
            for _ in 0 ..< Satin.maxBuffersInFlight {
                input.update(data: [UInt8](repeating: 99, count: 4097))
            }
            try complete(commandBuffer)
            XCTAssertEqual(read(encoded.output), [23, 23], "\(kind)")
            withExtendedLifetime((input, encoded.pipeline)) {}
        }
    }

    func testInputsSurviveRingWrapWithoutACommandBuffer() throws {
        for kind in BindingOwner.Kind.allCases {
            for length in [4, 4096, 4097] {
                let fixture = try makeFixture(kind: kind, inputIndex: .Custom0, length: length)
                let input = StructBuffer<UInt8>(device: device, count: length)
                fixture.owner.set(input, index: .Custom0)
                let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
                let encoder = try XCTUnwrap(commandBuffer.makeComputeCommandEncoder())
                encoder.setComputePipelineState(fixture.pipeline)
                var outputs: [MTLBuffer] = []
                for value in [UInt8(3), 5, 7, 11, 13] {
                    input.update(data: [UInt8](repeating: value, count: length))
                    let output = try XCTUnwrap(device.makeBuffer(length: 8, options: .storageModeShared))
                    fixture.owner.set(output, index: .Custom1)
                    fixture.owner.bind(encoder: encoder, commandBuffer: nil)
                    encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                    outputs.append(output)
                }
                encoder.endEncoding()
                try complete(commandBuffer)
                for (output, expected) in zip(outputs, [UInt32(3), 5, 7, 11, 13]) {
                    XCTAssertEqual(read(output), [expected, expected], "\(kind)")
                }
            }
        }
    }

    private func makeParameters(count: Int) -> ParameterGroup {
        let parameters = ParameterGroup("Snapshot", [FloatParameter("Amount", 1)])
        for index in 1 ..< count { parameters.append(FloatParameter("Padding \(index)", 0)) }
        return parameters
    }

    private struct Fixture {
        let owner: BindingOwner
        let pipeline: MTLComputePipelineState
    }

    private func makeFixture(kind: BindingOwner.Kind, inputIndex: ComputeBufferIndex, length: Int, lastByte: Int? = nil) throws -> Fixture {
        // For uniforms, read the first float's bytes, not trailing parameter padding. Struct
        // inputs also read their final byte, so truncating a large snapshot is observable.
        let sampledByte = lastByte ?? (length - 1)
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void snapshotInput(
            const device uchar *input [[buffer(\(inputIndex.rawValue))]],
            device uint *output [[buffer(\(ComputeBufferIndex.Custom1.rawValue))]]) {
            output[0] = input[0];
            output[1] = input[\(sampledByte)];
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let function = try XCTUnwrap(library.makeFunction(name: "snapshotInput"))
        var reflection: MTLComputePipelineReflection?
        let pipeline = try device.makeComputePipelineState(function: function, options: .bindingInfo, reflection: &reflection)
        let shader = ComputeShader(label: "Snapshot bindings")
        let owner = BindingOwner(kind: kind, device: device, shader: shader)
        shader.updatePipelineReflection = try XCTUnwrap(reflection)
        return Fixture(owner: owner, pipeline: pipeline)
    }

    private func encode(_ fixture: Fixture, commandBuffer suppliedCommandBuffer: MTLCommandBuffer? = nil) throws -> (commandBuffer: MTLCommandBuffer, output: MTLBuffer) {
        let commandBuffer = try suppliedCommandBuffer ?? XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeComputeCommandEncoder())
        let output = try XCTUnwrap(device.makeBuffer(length: 8, options: .storageModeShared))
        output.contents().initializeMemory(as: UInt8.self, repeating: 0xFF, count: 8)
        fixture.owner.set(output, index: .Custom1)
        encoder.setComputePipelineState(fixture.pipeline)
        fixture.owner.bind(encoder: encoder, commandBuffer: commandBuffer)
        encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        return (commandBuffer, output)
    }

    private func complete(_ commandBuffer: MTLCommandBuffer) throws {
        let finished = expectation(description: "compute completed")
        commandBuffer.addCompletedHandler { _ in finished.fulfill() }
        commandBuffer.commit()
        guard XCTWaiter.wait(for: [finished], timeout: 10) == .completed else {
            XCTFail("compute did not complete within ten seconds")
            throw CompletionError.timedOut
        }
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)
    }

    private func read(_ buffer: MTLBuffer) -> [UInt32] {
        let values = buffer.contents().assumingMemoryBound(to: UInt32.self)
        return [values[0], values[1]]
    }

    private enum CompletionError: Error { case timedOut }

    /// Avoids shader-file discovery only. Binding methods under test are the real implementation,
    /// and their used-buffer metadata comes from the real kernel's Metal reflection.
    private final class BindingProcessor: ComputeProcessor {
        override func setup() {}
    }

    private final class BindingSystem: ComputeSystem {
        override func setup() {}
    }

    private enum BindingOwner {
        enum Kind: CaseIterable { case processor, system }
        case processor(ComputeProcessor)
        case system(ComputeSystem)

        init(kind: Kind, device: MTLDevice, shader: ComputeShader) {
            let unusedURL = URL(fileURLWithPath: "/unused/SnapshotBindings.metal")
            switch kind {
                case .processor:
                    let processor = BindingProcessor(device: device, pipelineURL: unusedURL)
                    processor.shader = shader
                    self = .processor(processor)
                case .system:
                    let system = BindingSystem(device: device, pipelineURL: unusedURL, feedback: false, live: false)
                    system.shader = shader
                    self = .system(system)
            }
        }

        func set(_ input: UniformBuffer, index: ComputeBufferIndex) {
            switch self {
                case let .processor(processor): processor.set(input, index: index)
                case let .system(system): system.set(input, index: index)
            }
        }

        func set(_ input: BindableBuffer, index: ComputeBufferIndex) {
            switch self {
                case let .processor(processor): processor.set(input, index: index)
                case let .system(system): system.set(input, index: index)
            }
        }

        func set(_ input: MTLBuffer, index: ComputeBufferIndex) {
            switch self {
                case let .processor(processor): processor.set(input, index: index)
                case let .system(system): system.set(input, index: index)
            }
        }

        func installUniforms(_ parameters: ParameterGroup) throws -> UniformBuffer {
            switch self {
                case let .processor(processor):
                    processor.parameters = parameters
                    processor.setupUniforms()
                    return try XCTUnwrap(processor.uniforms)
                case let .system(system):
                    system.parameters = parameters
                    system.setupUniforms()
                    return try XCTUnwrap(system.uniforms)
            }
        }

        /// Binds as an update does: through `update(_ commandBuffer:)` when there is a command
        /// buffer, `update(_ computeEncoder:)` otherwise.
        func bind(encoder: MTLComputeCommandEncoder, commandBuffer: MTLCommandBuffer?) {
            switch self {
                case let .processor(processor):
                    processor.inputCopies.commandBuffer = commandBuffer
                    processor.bindUniforms(encoder)
                    processor.bindBuffers(encoder)
                case let .system(system):
                    system.inputCopies.commandBuffer = commandBuffer
                    system.bindUniforms(encoder)
                    system.bindBuffers(encoder)
            }
        }
    }
}
