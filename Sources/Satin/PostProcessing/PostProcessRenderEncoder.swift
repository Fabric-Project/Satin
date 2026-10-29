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

    /// Per-draw storage: the mesh's vertex uniforms in the arena, its packets in leased storage.
    private lazy var frameArena = FrameArena(allocator: context.gpuAllocator, label: "\(label) Frame Arena")
    private let packetStoragePool = PacketStoragePool()
    private var updateColorTexture = true
    private var updateColorMultisampleTexture = true
    /// The texture a pass draws into when its descriptor supplies none.
    public private(set) var colorTexture: MTLTexture?
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
    ) throws {
        let colorAttachment = colorAttachment(renderPassDescriptor)
        let originalTexture = colorAttachment.texture
        let originalResolveTexture = colorAttachment.resolveTexture
        defer {
            colorAttachment.texture = originalTexture
            colorAttachment.resolveTexture = originalResolveTexture
        }

        if context.sampleCount > 1 {
            colorAttachment.resolveTexture = renderTarget
        }
        else {
            colorAttachment.texture = renderTarget
        }

        try draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            camera: camera
        )
    }

    open func draw(
        frame: FrameTime,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        mesh: Mesh,
        camera: Camera
    ) throws {
        try draw(
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
    ) throws {
        let colorAttachment = colorAttachment(renderPassDescriptor)
        let originalTexture = colorAttachment.texture
        let originalResolveTexture = colorAttachment.resolveTexture
        defer {
            colorAttachment.texture = originalTexture
            colorAttachment.resolveTexture = originalResolveTexture
        }

        if context.sampleCount > 1 {
            colorAttachment.resolveTexture = renderTarget
        }
        else {
            colorAttachment.texture = renderTarget
        }

        try draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            mesh: mesh,
            cameras: cameras,
            viewports: viewports,
            viewMappings: viewMappings
        )
    }

    open func draw(
        frame: FrameTime,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        mesh: Mesh,
        cameras: [Camera],
        viewports: [MTLViewport],
        viewMappings: [MTLVertexAmplificationViewMapping] = []
    ) throws {
        let sealed = try prepareSubmission(frame: frame, renderPassDescriptor: renderPassDescriptor, mesh: mesh, cameras: cameras,
                                       viewports: viewports, viewMappings: viewMappings, preparationCommandBuffer: commandBuffer)
        try sealed.encode(into: commandBuffer)
    }

    /// Captures a postprocess pass without a command buffer. Custom GPU preparation must be
    /// scheduled separately before this pass; draw(...) retains its automatic immediate hooks.
    public func seal(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, mesh: Mesh,
                     cameras: [Camera], viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = []) throws -> SealedSubmission {
        try prepareSubmission(frame: frame, renderPassDescriptor: renderPassDescriptor, mesh: mesh, cameras: cameras,
                          viewports: viewports, viewMappings: viewMappings, preparationCommandBuffer: nil)
    }

    private func prepareSubmission(frame: FrameTime, renderPassDescriptor inputDescriptor: MTLRenderPassDescriptor, mesh: Mesh,
                                   cameras: [Camera], viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping],
                                   preparationCommandBuffer: MTLCommandBuffer?) throws -> SealedSubmission {
        let renderContext = fastRenderContext()
        let lease = frameArena.lease(frame: frame)
        let recorder = PacketRecorder(storage: packetStoragePool.lease(), lease: lease)
        var didRecord = false
        defer {
            if !didRecord {
                lease.finishRecording()
                packetStoragePool.returnStorage(recorder.storage)
            }
        }
        for camera in cameras { camera.update() }
        let views = cameras.enumerated().map { index, camera in
            RenderView(camera: camera, viewport: viewports.isEmpty ? .zero : viewports[min(index, viewports.count - 1)].float4, frame: frame)
        }
        mesh.update()
        if let commandBuffer = preparationCommandBuffer {
            try mesh.encode(in: EncodingContext(commandBuffer: commandBuffer, frame: frame, views: views, recorder: recorder))
        }
        mesh.beginOccurrence(frame: frame)
        let packets = try recorder.record(mesh, renderContext: renderContext, pass: .color, materialPass: .all, views: views)
        let descriptor = inputDescriptor.privateCopy()
        prepare(descriptor)
        var pass = RecordedRenderPass(descriptor: descriptor, label: label, viewports: viewports,
                                      amplificationCount: context.vertexAmplificationCount, viewMappings: viewMappings)
        pass.commands.append(.range(packets, viewIndex: 0))
        didRecord = true
        return SealedSubmission(frame: frame, recorder: recorder, lease: lease, pool: packetStoragePool, passes: [pass])
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
    lazy var forwardRenderContext = Context(
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
        emissivePixelFormat: context.emissivePixelFormat,
        gpuAllocator: context.gpuAllocator
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
