@testable import Satin
import Metal
import simd
import XCTest

final class PipelineBindingUsageTests: XCTestCase {
    private var device: MTLDevice!
    private var context: Context!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func geometry() -> Geometry {
        let geometry = Geometry(context: context)
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: [[-1,-1,0], [3,-1,0], [-1,3,0]]), for: .Position)
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: Array(repeating: [0,0,1], count: 3)), for: .Normal)
        geometry.addAttribute(Float2BufferAttribute(defaultValue: .zero, data: [[0,0], [2,0], [0,2]]), for: .Texcoord)
        return geometry
    }

    private func record(_ mesh: Mesh, pass: RenderPass, recorder: PacketRecorder? = nil) -> (PacketRecorder, Range<Int>) {
        mesh.castShadow = true
        mesh.update()
        mesh.beginOccurrence(frame: .zero)
        let recorder = recorder ?? PacketRecorder(storage: PacketStoragePool().lease(), lease: FrameArena(device: device).lease(frame: .zero))
        let camera = OrthographicCamera(context: context)
        let packets = recorder.record(mesh, renderContext: context, pass: pass, materialPass: .all, views: [RenderView(camera: camera, viewport: [0,0,32,32])])
        return (recorder, packets)
    }

    private func commands(_ recorder: PacketRecorder, _ packets: Range<Int>) -> [PacketCommand] {
        packets.flatMap { index in
            let packet = recorder.storage.packets[index]
            return Array(recorder.storage.commands[Int(packet.commandStart)..<Int(packet.commandStart + packet.commandCount)])
        }
    }

    private func vertexSlots(_ commands: [PacketCommand]) -> [VertexBufferIndex] {
        commands.compactMap {
            switch $0 {
            case let .vertexBuffer(_,_,slot), let .perViewVertexBuffer(_,_,slot): return slot
            default: return nil
            }
        }
    }

    func testDefaultShadowKeepsConservativeGeometryBindingsWithoutPacketPruning() {
        let mesh = Mesh(context: context, geometry: geometry(), material: PhysicalMaterial(context: context))
        let (recorder, packets) = record(mesh, pass: .shadow)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(Set(vertexSlots(commands(recorder, packets))), Set([.Position, .Normal, .Texcoord, .MaterialUniforms, .VertexUniforms]))
        let color = record(mesh, pass: .color, recorder: recorder)
        let slots = vertexSlots(commands(color.0, color.1))
        XCTAssertTrue(slots.contains(.Normal), "pruning a shadow must not alter colour usage")
        XCTAssertTrue(slots.contains(.MaterialUniforms))
    }

    private func shader(_ source: String, label: String = "UsageProbe") throws -> SourceShader {
        let directory = URL.temporaryDirectory.appending(path: "SatinBindingUsage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Shaders.metal")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return SourceShader(context: context, label: label, pipelineURL: url)
    }

    private func texture() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var pixel: UInt32 = .max
        texture.replace(region: MTLRegionMake2D(0,0,1,1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        return texture
    }

    func testCustomShadowKeepsItsOwnNormalUniformBufferAndDisplacementTexture() throws {
        let shader = try shader("""
        typedef struct { float amount; } UsageProbeUniforms;
        vertex float4 usageProbeShadowVertex(Vertex in [[stage_in]],
            constant VertexUniforms &view [[buffer(VertexBufferVertexUniforms)]],
            constant UsageProbeUniforms &uniforms [[buffer(VertexBufferMaterialUniforms)]],
            constant float &offset [[buffer(VertexBufferCustom0)]],
            texture2d<float> displacement [[texture(VertexTextureCustom0)]]) {
            return view.modelViewProjectionMatrix * float4(in.position + in.normal * (displacement.read(uint2(0)).r * uniforms.amount + offset), 1);
        }
        fragment half4 usageProbeFragment(VertexData in [[stage_in]]) { return half4(1); }
        """)
        let material = Material(shader: shader)
        material.set("Amount", Float(0.2))
        material.set(try texture(), index: VertexTextureIndex.Custom0)
        material.set(try texture(), index: VertexTextureIndex.Custom1)
        material.set(try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared)), index: VertexBufferIndex.Custom0)
        let (recorder, packets) = record(Mesh(context: context, geometry: geometry(), material: material), pass: .shadow)
        XCTAssertEqual(packets.count, 1)
        let recorded = commands(recorder, packets)
        let slots = vertexSlots(recorded)
        XCTAssertTrue(slots.contains(.Normal))
        XCTAssertTrue(slots.contains(.MaterialUniforms))
        XCTAssertTrue(slots.contains(.Custom0), "a shadow-only buffer must not depend on colour reflection")
        XCTAssertTrue(slots.contains(.Texcoord), "geometry binding is conservative again")
        let textures: [VertexTextureIndex] = recorded.compactMap { if case let .vertexTexture(_,slot) = $0 { return slot }; return nil }
        XCTAssertEqual(textures, [.Custom0, .Custom1], "shadow custom resources remain conservative without packet pruning")
        _ = record(Mesh(context: context, geometry: geometry(), material: material), pass: .color, recorder: recorder)
        let again = record(Mesh(context: context, geometry: geometry(), material: material), pass: .shadow, recorder: recorder)
        XCTAssertTrue(vertexSlots(commands(again.0, again.1)).contains(.Custom0))
        let source = try String(contentsOf: shader.pipelineURL, encoding: .utf8)
        try source.replacing("+ offset", with: "+ 0.0").write(to: shader.pipelineURL, atomically: true, encoding: .utf8)
        shader.reloadFromSource()
        let reloadedMesh = Mesh(context: context, geometry: geometry(), material: material)
        let reloaded = record(reloadedMesh, pass: .shadow)
        XCTAssertTrue(vertexSlots(commands(reloaded.0, reloaded.1)).contains(.Custom0), "registered custom shadow buffers stay available")
        let pipeline = try XCTUnwrap(shader.getPipeline(renderContext: context, shadow: true, layout: reloadedMesh.drawLayout))
        let usage = try XCTUnwrap(shader.resourceUsage(for: pipeline))
        XCTAssertFalse(usage.vertex.buffers.contains(VertexBufferIndex.Custom0.rawValue), "reload must rebuild cached requirements")
    }

    func testShadowFallbackToColourVertexKeepsItsRequiredResources() throws {
        let source = try shader("""
        vertex float4 usageProbeVertex(Vertex in [[stage_in]], constant float &offset [[buffer(VertexBufferCustom0)]]) {
            return float4(in.position + in.normal * offset, 1);
        }
        fragment half4 usageProbeFragment() { return half4(1); }
        """)
        var configuration = source.configuration
        configuration.shadowFunctionName = "unavailableShadowVertex"
        let fallback = SourceShader(configuration: configuration)
        let material = Material(shader: fallback)
        material.set(try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared)), index: VertexBufferIndex.Custom0)
        let (recorder, packets) = record(Mesh(context: context, geometry: geometry(), material: material), pass: .shadow)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(Set(vertexSlots(commands(recorder, packets))), Set([.Position, .Normal, .Texcoord, .Custom0]))
    }

    func testTextureArraysKeepEveryUsedElementAndDropUnrelatedTextures() throws {
        let shader = try shader("""
        fragment half4 usageProbeFragment(VertexData in [[stage_in]], array<texture2d<float>, 2> maps [[texture(FragmentTextureCustom0)]]) {
            return half4((maps[0].read(uint2(0)) + maps[1].read(uint2(0))) * 0.5);
        }
        """)
        let material = Material(shader: shader)
        for index in [FragmentTextureIndex.Custom0, .Custom1, .Custom2] { material.set(try texture(), index: index) }
        let mesh = Mesh(context: context, geometry: geometry(), material: material)
        let (recorder, packets) = record(mesh, pass: .color)
        XCTAssertEqual(packets.count, 1)
        let textures: [FragmentTextureIndex] = commands(recorder, packets).compactMap {
            if case let .fragmentTexture(_,slot) = $0 { return slot }; return nil
        }
        XCTAssertEqual(textures, [.Custom0, .Custom1])
    }

    func testDirectPacketFinishingPreservesTheSharedPrefixForOtherPipelines() throws {
        let material = PhysicalMaterial(context: context)
        let mesh = Mesh(context: context, geometry: geometry(), material: material)
        mesh.castShadow = true
        mesh.update()
        let firstShader = try XCTUnwrap(material.shader)
        let firstPipeline = try XCTUnwrap(firstShader.getPipeline(renderContext: context, shadow: true, layout: mesh.drawLayout))
        let firstUsage = try XCTUnwrap(firstShader.resourceUsage(for: firstPipeline))
        let secondShader = try shader("""
        vertex VertexData usageProbeVertex(Vertex in [[stage_in]], constant float &offset [[buffer(VertexBufferCustom0)]]) {
            VertexData out;
            out.position = float4(in.position.xy + offset, 0.5, 1);
            return out;
        }
        fragment half4 usageProbeFragment(VertexData in [[stage_in]]) { return half4(1); }
        """)
        let secondMaterial = Material(shader: secondShader)
        let secondMesh = Mesh(context: context, geometry: geometry(), material: secondMaterial)
        secondMesh.update()
        let secondPipeline = try XCTUnwrap(secondShader.getPipeline(renderContext: context, shadow: false, layout: secondMesh.drawLayout))
        let secondUsage = try XCTUnwrap(secondShader.resourceUsage(for: secondPipeline))
        let storage = PacketStoragePool().lease()
        storage.beginRecording(cullMode: .back, windingOrder: .counterClockwise, triangleFillMode: .fill, renderOrder: 0, debugLabel: "Shared prefix")
        storage.appendVertexBuffer(try XCTUnwrap(device.makeBuffer(length: 256)), offset: 0, slot: .Custom0)
        for (pipeline, usage) in [(firstPipeline, Optional(firstUsage)), (secondPipeline, Optional(secondUsage)), (firstPipeline, nil)] {
            storage.beginMaterial()
            storage.setPipeline(pipeline, usage: usage)
            storage.finishPacket(drawCall: .primitives(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1))
        }
        storage.endRecording()
        XCTAssertEqual(storage.packets.count, 3)
        let slots = storage.packets.map { packet in
            vertexSlots(Array(storage.commands[Int(packet.commandStart)..<Int(packet.commandStart + packet.commandCount)]))
        }
        XCTAssertEqual(slots[0], [.Custom0], "packet finishing no longer scans and compacts bindings")
        XCTAssertEqual(slots[1], [.Custom0], "a later pipeline still receives the original prefix")
        XCTAssertEqual(slots[2], [.Custom0], "an unreflected pipeline remains conservative")
    }

    private final class CutoutShader: SourceShader {
        var shadowBuilds = 0
        override func makeShadowPipeline() throws -> MTLRenderPipelineState? {
            shadowBuilds += 1
            guard let library = try ShaderLibraryCache.getLibrary(configuration: configuration.getLibraryConfiguration(), device: context.device) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexDescriptor = configuration.rendering.vertexDescriptor
            descriptor.vertexFunction = library.makeFunction(name: "usageProbeShadowVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "cutoutShadowFragment")
            descriptor.depthAttachmentPixelFormat = .depth32Float
            // Deliberately unreflected, as third-party makeShadowPipeline overrides can be.
            return try context.device.makeRenderPipelineState(descriptor: descriptor)
        }
    }

    func testUnreflectedCustomShadowFragmentKeepsCutoutTextureAndUniformsAndDrawsCorrectDepth() throws {
        let source = """
        typedef struct { float threshold; } UsageProbeUniforms;
        vertex VertexData usageProbeShadowVertex(Vertex in [[stage_in]]) {
            VertexData out;
            out.position = float4(in.position.xy, 0.5, 1);
            out.texcoord = in.texcoord;
            return out;
        }
        fragment void cutoutShadowFragment(VertexData in [[stage_in]],
            texture2d<float> mask [[texture(FragmentTextureCustom0)]],
            constant UsageProbeUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
            constexpr sampler sampleMask(address::clamp_to_edge, filter::nearest);
            if (mask.sample(sampleMask, in.texcoord).a < uniforms.threshold) discard_fragment();
        }
        fragment half4 usageProbeFragment(VertexData in [[stage_in]]) { return half4(1); }
        """
        let sourceShader = try shader(source)
        let shader = CutoutShader(context: context, label: "UsageProbe", pipelineURL: sourceShader.pipelineURL)
        let material = Material(shader: shader)
        material.set("Threshold", Float(0.5))
        let mesh = Mesh(context: context, geometry: geometry(), material: material)
        // Match the base configuration to exercise the base override, then use a layout variant.
        material.vertexDescriptor = mesh.geometry.vertexDescriptor
        material.castShadow = true
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var depths: [Float] = []
        for alpha: UInt8 in [0, 255] {
            let mask = try texture()
            var pixel: [UInt8] = [255, 255, 255, alpha]
            mask.replace(region: MTLRegionMake2D(0,0,1,1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
            material.set(mask, index: FragmentTextureIndex.Custom0)
            let (recorder, packets) = record(mesh, pass: .shadow)
            XCTAssertEqual(packets.count, 1)
            let recorded = commands(recorder, packets)
            XCTAssertTrue(recorded.contains { if case .fragmentTexture(_, .Custom0) = $0 { return true }; return false })
            XCTAssertTrue(recorded.contains { if case .fragmentBuffer(_,_, .MaterialUniforms) = $0 { return true }; return false })
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 32, height: 32, mipmapped: false)
            textureDescriptor.storageMode = .private
            textureDescriptor.usage = .renderTarget
            let target = try XCTUnwrap(device.makeTexture(descriptor: textureDescriptor))
            let descriptor = MTLRenderPassDescriptor()
            descriptor.depthAttachment.texture = target
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.clearDepth = 0
            var pass = RecordedRenderPass(descriptor: descriptor, label: "Cutout test", viewports: [MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)])
            pass.commands = [.range(packets, viewIndex: 0)]
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            try pass.encode(into: commandBuffer, recorder: recorder, state: RenderEncoderState())
            let readback = try XCTUnwrap(device.makeBuffer(length: 32 * 256, options: .storageModeShared))
            let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
            blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0,y: 0,z: 0), sourceSize: MTLSize(width: 32,height: 32,depth: 1), to: readback, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 32 * 256)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            XCTAssertEqual(commandBuffer.status, .completed)
            depths.append((readback.contents() + 16 * 256 + 16 * 4).load(as: Float.self))
            // The next operation uses a different layout/context key while keeping the override.
            material.vertexDescriptor = MTLVertexDescriptor()
        }
        XCTAssertEqual(depths[0], 0, accuracy: 0.001, "transparent texels must not cast a square")
        XCTAssertEqual(depths[1], 0.5, accuracy: 0.001, "opaque texels must still write shadow depth")
        XCTAssertGreaterThanOrEqual(shader.shadowBuilds, 2)
    }
}
