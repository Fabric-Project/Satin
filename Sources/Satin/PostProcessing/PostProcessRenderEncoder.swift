//
//  PostProcessRenderEncoder.swift
//  Satin
//
//  Created by OpenAI on 7/29/26.
//

import Metal
import simd

open class PostProcessRenderEncoder {
    public var label = "Satin PostProcessRenderEncoder"

    public let context: Context
    public let colorPixelFormat: MTLPixelFormat
    public let depthPixelFormat: MTLPixelFormat
    public let stencilPixelFormat: MTLPixelFormat

    public var size: (width: Float, height: Float) = (0, 0) {
        didSet {
            guard oldValue.width != size.width || oldValue.height != size.height else { return }
            updateViewport()
            updateColorTexture = true
            updateColorMultisampleTexture = true
        }
    }

    public var viewport = MTLViewport()
    public var clearColor: MTLClearColor
    public var colorLoadAction: MTLLoadAction
    public var colorStoreAction: MTLStoreAction
    public var frameBufferOnly: Bool {
        didSet {
            guard oldValue != frameBufferOnly else { return }
            updateColorTexture = true
            updateColorMultisampleTexture = true
        }
    }

    private struct RenderPassDescriptorState {
        let colorTexture: MTLTexture?
        let colorResolveTexture: MTLTexture?
        let colorLoadAction: MTLLoadAction
        let colorStoreAction: MTLStoreAction
        let colorClearColor: MTLClearColor
        let depthTexture: MTLTexture?
        let depthResolveTexture: MTLTexture?
        let depthLoadAction: MTLLoadAction
        let depthStoreAction: MTLStoreAction
        let depthClearDepth: Double
        let stencilTexture: MTLTexture?
        let stencilResolveTexture: MTLTexture?
        let stencilLoadAction: MTLLoadAction
        let stencilStoreAction: MTLStoreAction
        let stencilClearStencil: UInt32
        let renderTargetWidth: Int
        let renderTargetHeight: Int
    }

    /// Per-draw storage: the mesh's vertex uniforms in the arena, its packets in leased storage.
    private lazy var frameArena = FrameArena(device: context.device, label: "\(label) Frame Arena")
    private let packetStoragePool = PacketStoragePool()
    /// The state of the pass, reused by each draw.
    private let renderEncoderState = RenderEncoderState()
    private var updateColorTexture = true
    private var updateColorMultisampleTexture = true
    private var colorTexture: MTLTexture?
    private var colorMultisampleTexture: MTLTexture?

    private func colorAttachment(_ renderPassDescriptor: MTLRenderPassDescriptor) -> MTLRenderPassColorAttachmentDescriptor {
        guard let attachment = renderPassDescriptor.colorAttachments[0] else {
            preconditionFailure("PostProcessRenderEncoder requires color attachment 0.")
        }
        return attachment
    }

    public init(
        label: String = "Satin PostProcessRenderEncoder",
        context: Context,
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat = .invalid,
        stencilPixelFormat: MTLPixelFormat = .invalid,
        clearColor: simd_float4 = .init(0, 0, 0, 1),
        colorLoadAction: MTLLoadAction = .clear,
        colorStoreAction: MTLStoreAction = .store,
        frameBufferOnly: Bool = true
    ) {
        self.label = label
        self.context = context
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.stencilPixelFormat = stencilPixelFormat
        self.clearColor = MTLClearColor(clearColor)
        self.colorLoadAction = colorLoadAction
        self.colorStoreAction = colorStoreAction
        self.frameBufferOnly = frameBufferOnly
    }

    public convenience init(
        label: String = "Satin PostProcessRenderEncoder",
        context: Context,
        clearColor: simd_float4 = .init(0, 0, 0, 1),
        colorLoadAction: MTLLoadAction = .clear,
        colorStoreAction: MTLStoreAction = .store,
        frameBufferOnly: Bool = true
    ) {
        self.init(
            label: label,
            context: context,
            colorPixelFormat: context.colorPixelFormat,
            depthPixelFormat: context.depthPixelFormat,
            stencilPixelFormat: context.stencilPixelFormat,
            clearColor: clearColor,
            colorLoadAction: colorLoadAction,
            colorStoreAction: colorStoreAction,
            frameBufferOnly: frameBufferOnly
        )
    }

    open func resize(_ size: (width: Float, height: Float)) {
        self.size = size
    }

    open func draw(
        frame: FrameTime,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        mesh: Mesh,
        camera: Camera,
        renderTarget: MTLTexture
    ) {
        let colorAttachment = colorAttachment(renderPassDescriptor)
        let originalTexture = colorAttachment.texture
        let originalResolveTexture = colorAttachment.resolveTexture

        if context.sampleCount > 1 {
            colorAttachment.resolveTexture = renderTarget
        }
        else {
            colorAttachment.texture = renderTarget
        }

        draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            camera: camera
        )

        colorAttachment.texture = originalTexture
        colorAttachment.resolveTexture = originalResolveTexture
    }

    open func draw(
        frame: FrameTime,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        mesh: Mesh,
        camera: Camera
    ) {
        draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            cameras: [camera],
            viewports: [viewport]
        )
    }

    open func draw(
        frame: FrameTime,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        mesh: Mesh,
        cameras: [Camera],
        viewports: [MTLViewport],
        viewMappings: [MTLVertexAmplificationViewMapping] = [],
        renderTarget: MTLTexture
    ) {
        let colorAttachment = colorAttachment(renderPassDescriptor)
        let originalTexture = colorAttachment.texture
        let originalResolveTexture = colorAttachment.resolveTexture

        if context.sampleCount > 1 {
            colorAttachment.resolveTexture = renderTarget
        }
        else {
            colorAttachment.texture = renderTarget
        }

        draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            cameras: cameras,
            viewports: viewports,
            viewMappings: viewMappings
        )

        colorAttachment.texture = originalTexture
        colorAttachment.resolveTexture = originalResolveTexture
    }

    open func draw(
        frame: FrameTime,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        mesh: Mesh,
        cameras: [Camera],
        viewports: [MTLViewport],
        viewMappings: [MTLVertexAmplificationViewMapping] = []
    ) {
        let renderContext = fastRenderContext()
        let simdViewports = viewports.map(\.float4)

        for camera in cameras {
            camera.update()
        }

        let storage = packetStoragePool.lease()
        defer { packetStoragePool.returnStorage(storage) }
        let recorder = PacketRecorder(storage: storage, arena: frameArena, commandBuffer: commandBuffer, frame: frame)
        var views: [RenderView] = []
        for (index, camera) in cameras.enumerated() {
            let viewport = simdViewports.isEmpty ? simd_float4.zero : simdViewports[min(index, simdViewports.count - 1)]
            views.append(RenderView(camera: camera, viewport: viewport, frame: frame))
        }

        mesh.update()
        mesh.encode(in: EncodingContext(commandBuffer: commandBuffer, frame: frame, views: views, recorder: recorder))
        mesh.beginOccurrence(frame: frame)
        // One amplified draw covers every view.
        let packets = recorder.record(mesh, renderContext: renderContext, pass: .color, materialPass: .all, views: views)

        let descriptorState = saveState(renderPassDescriptor)
        defer { restoreState(descriptorState, to: renderPassDescriptor) }

        prepare(renderPassDescriptor)

        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        renderCommandEncoder.label = label
        renderEncoderState.begin(renderEncoder: renderCommandEncoder, renderPassDescriptor: renderPassDescriptor)

        if context.vertexAmplificationCount > 1 {
            var mappings = viewMappings
            if mappings.isEmpty {
                mappings = (0..<context.vertexAmplificationCount).map {
                    MTLVertexAmplificationViewMapping(
                        viewportArrayIndexOffset: UInt32($0),
                        renderTargetArrayIndexOffset: UInt32($0)
                    )
                }
            }
            renderEncoderState.setPassVertexAmplification(count: context.vertexAmplificationCount, viewMappings: mappings)
        }

        if !viewports.isEmpty {
            renderEncoderState.setPassViewports(viewports)
        }

        recorder.encode(packets, into: renderEncoderState)
        renderCommandEncoder.endEncoding()
        renderEncoderState.end()
    }

    private func saveState(_ renderPassDescriptor: MTLRenderPassDescriptor) -> RenderPassDescriptorState {
        let colorAttachment = colorAttachment(renderPassDescriptor)
        return RenderPassDescriptorState(
            colorTexture: colorAttachment.texture,
            colorResolveTexture: colorAttachment.resolveTexture,
            colorLoadAction: colorAttachment.loadAction,
            colorStoreAction: colorAttachment.storeAction,
            colorClearColor: colorAttachment.clearColor,
            depthTexture: renderPassDescriptor.depthAttachment.texture,
            depthResolveTexture: renderPassDescriptor.depthAttachment.resolveTexture,
            depthLoadAction: renderPassDescriptor.depthAttachment.loadAction,
            depthStoreAction: renderPassDescriptor.depthAttachment.storeAction,
            depthClearDepth: renderPassDescriptor.depthAttachment.clearDepth,
            stencilTexture: renderPassDescriptor.stencilAttachment.texture,
            stencilResolveTexture: renderPassDescriptor.stencilAttachment.resolveTexture,
            stencilLoadAction: renderPassDescriptor.stencilAttachment.loadAction,
            stencilStoreAction: renderPassDescriptor.stencilAttachment.storeAction,
            stencilClearStencil: renderPassDescriptor.stencilAttachment.clearStencil,
            renderTargetWidth: renderPassDescriptor.renderTargetWidth,
            renderTargetHeight: renderPassDescriptor.renderTargetHeight
        )
    }

    private func restoreState(_ state: RenderPassDescriptorState, to renderPassDescriptor: MTLRenderPassDescriptor) {
        let colorAttachment = colorAttachment(renderPassDescriptor)
        colorAttachment.texture = state.colorTexture
        colorAttachment.resolveTexture = state.colorResolveTexture
        colorAttachment.loadAction = state.colorLoadAction
        colorAttachment.storeAction = state.colorStoreAction
        colorAttachment.clearColor = state.colorClearColor

        renderPassDescriptor.depthAttachment.texture = state.depthTexture
        renderPassDescriptor.depthAttachment.resolveTexture = state.depthResolveTexture
        renderPassDescriptor.depthAttachment.loadAction = state.depthLoadAction
        renderPassDescriptor.depthAttachment.storeAction = state.depthStoreAction
        renderPassDescriptor.depthAttachment.clearDepth = state.depthClearDepth
        renderPassDescriptor.stencilAttachment.texture = state.stencilTexture
        renderPassDescriptor.stencilAttachment.resolveTexture = state.stencilResolveTexture
        renderPassDescriptor.stencilAttachment.loadAction = state.stencilLoadAction
        renderPassDescriptor.stencilAttachment.storeAction = state.stencilStoreAction
        renderPassDescriptor.stencilAttachment.clearStencil = state.stencilClearStencil
        renderPassDescriptor.renderTargetWidth = state.renderTargetWidth
        renderPassDescriptor.renderTargetHeight = state.renderTargetHeight
    }

    private func prepare(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        let colorAttachment = colorAttachment(renderPassDescriptor)

        if context.sampleCount > 1 {
            if colorAttachment.texture?.sampleCount != context.sampleCount {
                setupColorMultisampleTexture()
                colorAttachment.texture = colorMultisampleTexture
            }

            if colorAttachment.resolveTexture == nil {
                setupColorTexture()
                colorAttachment.resolveTexture = colorTexture
            }

            colorAttachment.storeAction = colorStoreAction == .store || colorStoreAction == .storeAndMultisampleResolve
                ? .storeAndMultisampleResolve
                : .multisampleResolve
        }
        else {
            if colorAttachment.texture == nil {
                setupColorTexture()
                colorAttachment.texture = colorTexture
            }

            colorAttachment.storeAction = colorStoreAction == .store || colorStoreAction == .storeAndMultisampleResolve
                ? .store
                : .dontCare
        }

        colorAttachment.loadAction = colorLoadAction
        colorAttachment.clearColor = clearColor

        renderPassDescriptor.renderTargetWidth = colorAttachment.resolveTexture?.width ?? colorAttachment.texture?.width ?? Int(size.width)
        renderPassDescriptor.renderTargetHeight = colorAttachment.resolveTexture?.height ?? colorAttachment.texture?.height ?? Int(size.height)

        if depthPixelFormat == .invalid {
            renderPassDescriptor.depthAttachment.texture = nil
            renderPassDescriptor.depthAttachment.resolveTexture = nil
        }

        if stencilPixelFormat == .invalid {
            renderPassDescriptor.stencilAttachment.texture = nil
            renderPassDescriptor.stencilAttachment.resolveTexture = nil
        }
    }

    /// The forward context for this encoder's formats, which never change.
    private lazy var forwardRenderContext = Context(
        device: context.device,
        sampleCount: context.sampleCount,
        colorPixelFormat: colorPixelFormat,
        depthPixelFormat: depthPixelFormat,
        stencilPixelFormat: stencilPixelFormat,
        vertexAmplificationCount: context.vertexAmplificationCount,
        maxBuffersInFlight: context.maxBuffersInFlight,
        renderingMode: .forward,
        activeOutputs: .color,
        alphaOitEnabled: false,
        albedoPixelFormat: context.albedoPixelFormat,
        normalsPixelFormat: context.normalsPixelFormat,
        pbrPixelFormat: context.pbrPixelFormat,
        velocityPixelFormat: context.velocityPixelFormat,
        emissivePixelFormat: context.emissivePixelFormat
    )

    private func fastRenderContext() -> Context {
        forwardRenderContext
    }

    private func setupColorTexture() {
        guard updateColorTexture, colorPixelFormat != .invalid, size.width > 0, size.height > 0 else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = frameBufferOnly ? .renderTarget : [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .memoryless

        colorTexture = context.device.makeTexture(descriptor: descriptor)
        colorTexture?.label = label + " Color Texture"
        updateColorTexture = false
    }

    private func setupColorMultisampleTexture() {
        guard updateColorMultisampleTexture,
              colorPixelFormat != .invalid,
              context.sampleCount > 1,
              size.width > 0,
              size.height > 0
        else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.sampleCount = context.sampleCount
        descriptor.usage = .renderTarget
        descriptor.storageMode = .memoryless

        colorMultisampleTexture = context.device.makeTexture(descriptor: descriptor)
        colorMultisampleTexture?.label = label + " Color Multisample Texture"
        updateColorMultisampleTexture = false
    }

    private func updateViewport() {
        viewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(size.width),
            height: Double(size.height),
            znear: 0,
            zfar: 1
        )
    }
}
