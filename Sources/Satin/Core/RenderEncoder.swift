//
//  RenderEncoder.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal
import simd

open class RenderEncoder {
    public var label = "Satin RenderEncoder"

    public var onUpdate: (() -> Void)?


    // MARK: - Configuration

    /// What the settings below are set to.
    private var configuration: SubmissionConfiguration
    /// While a submission draws or records: the settings it was made with. The settings below report
    /// these then, and setting them changes only `configuration`, for later submissions.
    private var activeConfiguration: SubmissionConfiguration?

    public var sortObjects: Bool {
        get { activeConfiguration?.sortObjects ?? configuration.sortObjects }
        set { configuration.sortObjects = newValue }
    }

    public let context: Context
    public let colorPixelFormat: MTLPixelFormat
    public let depthPixelFormat: MTLPixelFormat
    public let stencilPixelFormat: MTLPixelFormat

    public var size: (width: Float, height: Float) = (0, 0) {
        didSet {
            if oldValue.width != size.width || oldValue.height != size.height {
                updateViewport()

                updateColorTexture = true
                updateColorMultisampleTexture = true

                updateDepthTexture = true
                updateDepthMultisampleTexture = true

                updateStencilTexture = true
                updateStencilMultisampleTexture = true

                updateNormalTexture = true
                updateVelocityTexture = true
                updateAlbedoTexture = true
                updatePBRTexture = true
                updateEmissiveTexture = true
            }
        }
    }

    // MARK: - Color Textures

    public var clearColor: MTLClearColor {
        get { activeConfiguration?.clearColor ?? configuration.clearColor }
        set { configuration.clearColor = newValue }
    }

    private var updateColorTexture = true
    public private(set) var colorTexture: MTLTexture?
    public var colorTextureStorageMode: MTLStorageMode = .memoryless {
        didSet {
            if oldValue != colorTextureStorageMode {
                updateColorTexture = true
            }
        }
    }

    private var updateColorMultisampleTexture = true
    public private(set) var colorMultisampleTexture: MTLTexture?
    public var colorMultisampleTextureStorageMode: MTLStorageMode = .memoryless {
        didSet {
            if oldValue != colorMultisampleTextureStorageMode {
                updateColorMultisampleTexture = true
            }
        }
    }

    public var colorLoadAction: MTLLoadAction {
        get { activeConfiguration?.colorLoadAction ?? configuration.colorLoadAction }
        set { configuration.colorLoadAction = newValue }
    }

    public var colorStoreAction: MTLStoreAction {
        get { activeConfiguration?.colorStoreAction ?? configuration.colorStoreAction }
        set { configuration.colorStoreAction = newValue }
    }

    // MARK: - Depth Textures

    public var clearDepth: Double {
        get { activeConfiguration?.clearDepth ?? configuration.clearDepth }
        set { configuration.clearDepth = newValue }
    }

    public var updateDepthTexture = true
    public private(set) var depthTexture: MTLTexture?
    public var depthTextureStorageMode: MTLStorageMode = .memoryless {
        didSet {
            if oldValue != depthTextureStorageMode {
                updateDepthTexture = true
            }
        }
    }

    public var updateDepthMultisampleTexture = true
    public private(set) var depthMultisampleTexture: MTLTexture?
    public var depthMultisampleTextureStorageMode: MTLStorageMode = .memoryless {
        didSet {
            if oldValue != depthMultisampleTextureStorageMode {
                updateDepthMultisampleTexture = true
            }
        }
    }

    public var depthLoadAction: MTLLoadAction {
        get { activeConfiguration?.depthLoadAction ?? configuration.depthLoadAction }
        set { configuration.depthLoadAction = newValue }
    }

    public var depthStoreAction: MTLStoreAction {
        get { activeConfiguration?.depthStoreAction ?? configuration.depthStoreAction }
        set { configuration.depthStoreAction = newValue }
    }

    // MARK: - Stencil Textures

    public var clearStencil: UInt32 {
        get { activeConfiguration?.clearStencil ?? configuration.clearStencil }
        set { configuration.clearStencil = newValue }
    }

    public var updateStencilTexture = true
    public var stencilTexture: MTLTexture?
    public var stencilTextureStorageMode: MTLStorageMode = .memoryless {
        didSet {
            if oldValue != stencilTextureStorageMode {
                updateStencilTexture = true
            }
        }
    }

    public var updateStencilMultisampleTexture = true
    public var stencilMultisampleTexture: MTLTexture?
    public var stencilMultisampleTextureStorageMode: MTLStorageMode = .memoryless {
        didSet {
            if oldValue != stencilMultisampleTextureStorageMode {
                updateStencilMultisampleTexture = true
            }
        }
    }

    public var stencilLoadAction: MTLLoadAction {
        get { activeConfiguration?.stencilLoadAction ?? configuration.stencilLoadAction }
        set { configuration.stencilLoadAction = newValue }
    }

    public var stencilStoreAction: MTLStoreAction {
        get { activeConfiguration?.stencilStoreAction ?? configuration.stencilStoreAction }
        set { configuration.stencilStoreAction = newValue }
    }

    // MARK: - RenderEncoder Outputs

    /// Controls whether the renderer runs a traditional forward pass, a forward MRT pass,
    /// or the deferred geometry stage. Switching modes compiles new pipeline variants on
    /// the next frame, so avoid changing this every frame.
    public var renderingMode: RenderingMode {
        get { activeConfiguration?.renderingMode ?? configuration.renderingMode }
        set { configuration.renderingMode = newValue }
    }

    /// Declares which auxiliary outputs the renderer should produce in addition to color.
    /// Each active flag adds a texture allocation and an extra color attachment write.
    /// The current MRT path requires `context.sampleCount == 1` whenever auxiliary outputs
    /// are enabled.
    public var activeOutputs: RendererOutputs {
        get { activeConfiguration?.activeOutputs ?? configuration.activeOutputs }
        set { configuration.activeOutputs = newValue }
    }

    /// Legacy compatibility bridge for the old prepass API.
    ///
    /// Setting this promotes `.forward` renderers to `.forwardPlus` so existing callers that
    /// requested velocity or normals continue producing those textures.
    public var outputs: RendererOutputs {
        get { activeOutputs.subtracting([.color]) }
        set {
            activeOutputs = normalizedOutputs(newValue)
            if renderingMode == .forward, !newValue.isEmpty {
                renderingMode = .forwardPlus
            }
        }
    }

    private var updateAlbedoTexture = true
    public private(set) var albedoTexture: MTLTexture?
    public var albedoTextureStorageMode: MTLStorageMode = .private {
        didSet {
            if oldValue != albedoTextureStorageMode { updateAlbedoTexture = true }
        }
    }

    private var updateNormalTexture = true
    public private(set) var normalTexture: MTLTexture?
    public var normalTextureStorageMode: MTLStorageMode = .private {
        didSet {
            if oldValue != normalTextureStorageMode { updateNormalTexture = true }
        }
    }

    private var updatePBRTexture = true
    public private(set) var pbrTexture: MTLTexture?
    public var pbrTextureStorageMode: MTLStorageMode = .private {
        didSet {
            if oldValue != pbrTextureStorageMode { updatePBRTexture = true }
        }
    }

    private var updateVelocityTexture = true
    public private(set) var velocityTexture: MTLTexture?
    public var velocityTextureStorageMode: MTLStorageMode = .private {
        didSet {
            if oldValue != velocityTextureStorageMode { updateVelocityTexture = true }
        }
    }

    private var updateEmissiveTexture = true
    public private(set) var emissiveTexture: MTLTexture?
    public var emissiveTextureStorageMode: MTLStorageMode = .private {
        didSet {
            if oldValue != emissiveTextureStorageMode { updateEmissiveTexture = true }
        }
    }
    
    // MARK: -

    public var viewport = MTLViewport()

    public var invertViewportNearFar = false {
        didSet {
            if invertViewportNearFar != oldValue {
                updateViewport()
            }
        }
    }

    // The encoding phase applied when drawing a collected set of renderables.
    // Controls which render Context is built (shader defines, G-buffer outputs, OIT flag)
    // and the recording context's material pass, which Mesh.materialMatchesCurrentPass reads to
    // gate per-material drawing within a single encoder.
    private enum MaterialPassType: Int {
        // All opaque geometry in a plain forward pass. No G-buffer outputs, no OIT.
        // Used for every opaque renderable in .forward rendering mode (surface-lit and
        // unlit alike). Its recordings draw every non-transparent material.
        case forwardOpaque

        // Opaque surface-lit geometry writing to the G-buffer. Active only in .forwardPlus
        // and .deferredGeometry modes. Enables OUTPUT_* defines so materials write albedo,
        // normals, PBR, velocity, and emissive attachments alongside the colour buffer.
        case surfaceOpaque

        // Opaque unlit geometry rendered forward, never to the G-buffer.
        // Used in .forwardPlus and .deferredGeometry after the surface pass so unlit
        // objects (skybox, fullscreen quads, etc.) write only to the colour attachment.
        case unlitOpaque

        // Image-block OIT pass on Apple4+ devices when context.alphaOitEnabled is true.
        // Sets alphaOitEnabled on the render context, injecting the ALPHA_OIT define so
        // material fragment shaders write into the per-pixel tile imageblock rather than
        // the framebuffer. A fullscreen blend quad then composites the sorted layers.
        case alphaTransparent

        // Hardware alpha blending for all transparent geometry that is not handled by
        // image-block OIT: additive, subtract, custom blend modes, and blending == .alpha
        // when the renderer context does not support OIT (alphaOitEnabled = false or
        // non-Apple4 hardware). No special defines — standard src/dst blend equations apply.
        case classicTransparent
    }

    // Determines which renderables are collected into a pass before encoding begins.
    // routePassEntries(route:) filters the scene's render lists by these predicates.
    // Route and MaterialPassType are separate because the same route can map to different
    // phases depending on rendering mode (e.g. .opaque → .forwardOpaque in .forward, but
    // opaque geometry is split into .surfaceOpaque + .unlitOpaque in .forwardPlus/.deferredGeometry).
    private enum RenderRoute: Int, CaseIterable {
        // All opaque geometry (blending == .disabled), regardless of lighting model.
        // Used as a single bucket in .forward mode. In other modes, opaque geometry is
        // collected via .surfaceOpaque and .unlitOpaque instead.
        case opaque

        // Opaque surface-lit geometry (lightingModel == .surface && blending == .disabled).
        // Subset of .opaque; separated so G-buffer output configuration can be applied.
        case surfaceOpaque

        // Opaque unlit geometry (lightingModel == .unlit && blending == .disabled).
        // Subset of .opaque; always encoded forward-only without G-buffer writes.
        case unlitOpaque

        // Alpha materials destined for image-block OIT:
        // blending == .alpha && supportsAlphaOrderIndependentTransparency && supportsAlphaOit.
        // Empty on non-Apple4 hardware or when context.alphaOitEnabled is false.
        case alphaTransparent

        // All remaining transparent geometry: any blending mode that is not handled by
        // image-block OIT. Includes additive, subtract, custom, and blending == .alpha
        // when OIT is unavailable (supportsAlphaOit == false).
        case classicTransparent
    }

    /// One render layer's share of a route: the packets recorded for it, in draw order.
    private struct RenderRouteEntry {
        let pass: Int
        let packets: ArraySlice<Int>
    }

    private struct ColorAttachmentState {
        let texture: MTLTexture?
        let resolveTexture: MTLTexture?
        let loadAction: MTLLoadAction
        let storeAction: MTLStoreAction
        let clearColor: MTLClearColor
    }

    /// The context for each rendering mode, pass type and output set, made on first use, at
    /// `(mode × pass types + phase) × output sets + outputs`; nil until then. The formats are fixed
    /// for the encoder's life, so nothing ever invalidates one.
    private var renderContexts: [Context?] = []
    /// Every combination of the six `RendererOutputs` flags.
    private static let renderContextOutputSets = 64
    private static let renderContextPassTypes = 5

    private static func renderingModeIndex(_ mode: RenderingMode) -> Int {
        switch mode {
        case .forward: return 0
        case .forwardPlus: return 1
        case .deferredGeometry: return 2
        }
    }
    private let supportsAlphaOit: Bool
    private let alphaOitTileSize = MTLSize(width: 32, height: 16, depth: 1)
    private lazy var alphaOitResources = AlphaOitResources(renderer: self)

    private func colorAttachment(_ renderPassDescriptor: MTLRenderPassDescriptor, index: Int) -> MTLRenderPassColorAttachmentDescriptor? {
        renderPassDescriptor.colorAttachments[index]
    }

    /// What the current update pass collected from the scene, and how it walks the scene.
    private let renderCollection = RenderCollection()
    private let sceneTraversal = SceneTraversal()
    /// Records each renderable's draw before executing it; reused for every draw.
    /// Per-draw storage: vertex uniforms in the arena, packets in storage leased for one draw.
    private lazy var frameArena = FrameArena(device: context.device, label: "\(label) Frame Arena")
    let packetStoragePool = PacketStoragePool()
    /// The state of whichever of this encoder's passes is encoding: one at a time, reused.
    private var preparedPasses: [RecordedRenderPass] = []
    private var preparingViews: [RenderView] = []
    /// Records each frame's shadow casters once for every shadow pass.
    private let shadowCasterRecording = ShadowCasterRecording()
    private var shadowsToDraw = ContiguousArray<Shadow>()
    /// The draw in progress: set for the length of `draw`.
    private var recorder: PacketRecorder?
    /// The renderables of a scene being recorded into a submission, reused across records.
    private var recordedRenderables: [Renderable] = []
    /// This draw's render layers, ascending: every layer with packets from the scene or a record. A
    /// layer's position here is its pass index.
    private var passLayers: [Int] = []
    /// Packet indices by route and pass, `packetBuckets[route.rawValue][pass]`, in draw order.
    private var packetBuckets: [[[Int]]] = Array(repeating: [], count: RenderRoute.allCases.count)
    /// Each route's entries for this draw, by route raw value; built once after recording.
    private var routeEntries: [[RenderRouteEntry]] = Array(repeating: [], count: RenderRoute.allCases.count)
    /// CPU light data is rebuilt only when a light, its transform, properties or assigned indices
    /// change. Every draw snapshots the cached values into its own arena storage.
    private struct UploadedLight {
        enum Identity: Equatable {
            case object(ObjectIdentifier)
            case recorded(RecordedLightIdentity)
        }
        let identity: Identity
        let worldRevision: UInt64
        let lightRevision: UInt64
        let shadowIndex: Int
        let projectorIndex: Int
    }

    private var uploadedLights: [UploadedLight] = []
    /// The light data last uploaded, in light order.
    private(set) var uploadedLightData: [LightData] = []
    /// Light-data rebuilds so far (not the number of per-draw arena copies); for tests.
    private(set) var lightDataUploadCount = 0

    private var directShadowLights = [Light]()
    private var directShadowTextures = [MTLTexture?]()

    private var projectorLights = [Light]()
    private var projectorTextures = [MTLTexture?]()

    private var activeEnvironmentIntensity: Float = 1.0
    private var activeReflectionTexture: MTLTexture?
    private var activeIrradianceTexture: MTLTexture?
    private var activeBrdfTexture: MTLTexture?
    private var activeReflectionTexcoordTransform = matrix_identity_float3x3
    private var activeIrradianceTexcoordTransform = matrix_identity_float3x3

    private lazy var deferredLightingMaterial = DeferredLightingMaterial(context: context)
    private lazy var deferredLightingMesh: Mesh = {
        let mesh = Mesh(
            context: context,
            label: label + " Deferred Lighting Mesh",
            geometry: QuadGeometry(context: context),
            material: deferredLightingMaterial
        )
        mesh.cullMode = .none
        mesh.castShadow = false
        mesh.receiveShadow = false
        return mesh
    }()
    private lazy var deferredLightingCamera = OrthographicCamera(context: context)

    var frameBufferOnly: Bool {
        didSet {
            if frameBufferOnly != oldValue {
                updateColorTexture = true
                updateDepthTexture = true
                updateStencilTexture = true
            }
        }
    }

    // MARK: - Init

    public init(
        label: String = "Satin RenderEncoder",
        context: Context,
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat,
        stencilPixelFormat: MTLPixelFormat,
        sortObjects: Bool = true,
        clearColor: simd_float4 = .init(0, 0, 0, 1),
        colorLoadAction: MTLLoadAction = .clear,
        colorStoreAction: MTLStoreAction = .store,
        clearDepth: Double = 0,
        depthLoadAction: MTLLoadAction = .clear,
        depthStoreAction: MTLStoreAction = .store,
        clearStencil: UInt32 = 0,
        stencilLoadAction: MTLLoadAction = .clear,
        stencilStoreAction: MTLStoreAction = .store,
        frameBufferOnly: Bool = true
    ) {
        self.label = label
        self.context = context
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.stencilPixelFormat = stencilPixelFormat
        configuration = SubmissionConfiguration(
            renderingMode: context.renderingMode,
            activeOutputs: RendererOutputs(rawValue: context.activeOutputs.rawValue | RendererOutputs.color.rawValue),
            sortObjects: sortObjects,
            clearColor: MTLClearColor(clearColor),
            colorLoadAction: colorLoadAction,
            colorStoreAction: colorStoreAction,
            clearDepth: clearDepth,
            depthLoadAction: depthLoadAction,
            depthStoreAction: depthStoreAction,
            clearStencil: clearStencil,
            stencilLoadAction: stencilLoadAction,
            stencilStoreAction: stencilStoreAction
        )

        self.frameBufferOnly = frameBufferOnly
        self.supportsAlphaOit = context.device.supportsFamily(.apple4)
            && context.alphaOitEnabled
            && context.vertexAmplificationCount <= 1
    }

    public convenience init(
        label: String = "Satin RenderEncoder",
        context: Context,
        sortObjects: Bool = true,
        clearColor: simd_float4 = .init(0, 0, 0, 1),
        colorLoadAction: MTLLoadAction = .clear,
        colorStoreAction: MTLStoreAction = .store,
        clearDepth: Double = 0,
        depthLoadAction: MTLLoadAction = .clear,
        depthStoreAction: MTLStoreAction = .store,
        clearStencil: UInt32 = 0,
        stencilLoadAction: MTLLoadAction = .clear,
        stencilStoreAction: MTLStoreAction = .store,
        frameBufferOnly: Bool = true
    ) {
        self.init(
            label: label,
            context: context,
            colorPixelFormat: context.colorPixelFormat,
            depthPixelFormat: context.depthPixelFormat,
            stencilPixelFormat: context.stencilPixelFormat,
            sortObjects: sortObjects,
            clearColor: clearColor,
            colorLoadAction: colorLoadAction,
            colorStoreAction: colorStoreAction,
            clearDepth: clearDepth,
            depthLoadAction: depthLoadAction,
            depthStoreAction: depthStoreAction,
            clearStencil: clearStencil,
            stencilLoadAction: stencilLoadAction,
            stencilStoreAction: stencilStoreAction,
            frameBufferOnly: frameBufferOnly
        )
    }

    public func setClearColor(_ color: simd_float4) {
        clearColor = .init(color)
    }

    // MARK: - Drawing

    public func draw(
        frame: FrameTime,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        scene: Object,
        camera: Camera,
        viewport: MTLViewport? = nil,
        renderTarget: MTLTexture
    ) throws {
        if context.sampleCount > 1 {
            let resolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
            // Restored on a throw too: the caller's descriptor is theirs.
            defer { renderPassDescriptor.colorAttachments[0].resolveTexture = resolveTexture }
            renderPassDescriptor.colorAttachments[0].resolveTexture = renderTarget
            try draw(
                frame: frame,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: [camera],
                viewports: [viewport ?? self.viewport]
            )
        } else {
            let renderTexture = renderPassDescriptor.colorAttachments[0].texture
            // Restored on a throw too: the caller's descriptor is theirs.
            defer { renderPassDescriptor.colorAttachments[0].texture = renderTexture }
            renderPassDescriptor.colorAttachments[0].texture = renderTarget
            try draw(
                frame: frame,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: [camera],
                viewports: [viewport ?? self.viewport]
            )
        }
    }

    public func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, cameras: [Camera], viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = [], renderTarget: MTLTexture) throws {
        if context.sampleCount > 1 {
            let resolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
            // Restored on a throw too: the caller's descriptor is theirs.
            defer { renderPassDescriptor.colorAttachments[0].resolveTexture = resolveTexture }
            renderPassDescriptor.colorAttachments[0].resolveTexture = renderTarget
            try draw(
                frame: frame,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: cameras,
                viewports: viewports,
                viewMappings: viewMappings
            )
        } else {
            let renderTexture = renderPassDescriptor.colorAttachments[0].texture
            // Restored on a throw too: the caller's descriptor is theirs.
            defer { renderPassDescriptor.colorAttachments[0].texture = renderTexture }
            renderPassDescriptor.colorAttachments[0].texture = renderTarget
            try draw(
                frame: frame,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: cameras,
                viewports: viewports,
                viewMappings: viewMappings
            )
        }
    }

    // https://developer.apple.com/documentation/metal/render_passes/improving_rendering_performance_with_vertex_amplification?language=objc
    // https://developer.apple.com/documentation/metal/render_passes/rendering_to_multiple_viewports_in_a_draw_command?language=objc

    public func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, camera: Camera, viewport: MTLViewport? = nil) throws {
        try draw(
            frame: frame,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            cameras: [camera],
            viewports: [viewport ?? self.viewport]
        )
    }

    /// Draws the scene using the current render graph.
    ///
    /// Shadow passes run before the main scene pass. Surface materials render first according to
    /// `renderingMode`; unlit materials always render in a subsequent forward pass on top.
    public func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, cameras: [Camera], viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = []) throws {
        RecordingProfile.noteFrame(frame.frameNumber)
        RecordingProfile.begin(.scenePlanning)
        defer { RecordingProfile.end() }
        let builder = makeSubmissionBuilder(frame: frame, cameras: cameras, viewports: viewports)
        try builder.record(scene: scene, renderPassDescriptor: renderPassDescriptor, viewMappings: viewMappings, preparationCommandBuffer: commandBuffer)
        let sealed = try builder.seal()
        RecordingProfile.begin(.replay)
        defer { RecordingProfile.end() }
        try sealed.encode(into: commandBuffer)
    }

    /// Creates a producer-only operation with frozen views and renderer settings. Record its scene
    /// and pass descriptor before sealing; the sealed work can encode after subsequent recordings.
    public func makeSubmissionBuilder(frame: FrameTime, cameras: [Camera], viewports: [MTLViewport]) -> SubmissionBuilder {
        for camera in cameras { camera.update() }
        let lease = frameArena.lease(frame: frame)
        let recorder = PacketRecorder(storage: packetStoragePool.lease(), lease: lease)
        let destination = RenderDestination(colorPixelFormats: [colorPixelFormat], depthPixelFormat: depthPixelFormat,
                                            stencilPixelFormat: stencilPixelFormat, sampleCount: context.sampleCount,
                                            width: Int(size.width), height: Int(size.height), viewCount: max(context.vertexAmplificationCount, 1))
        return SubmissionBuilder(encoder: self, recorder: recorder, lease: lease, frame: frame, destination: destination,
                                 configuration: activeConfiguration ?? configuration, cameras: cameras, viewports: viewports, pool: packetStoragePool)
    }

    /// Gives up `sealed` without encoding it: what it holds is released, and the shadows its
    /// recording cleaned are marked to draw again, since their passes will never run. Call it on the
    /// producer. Dropping an unencoded builder or submission also invalidates its pending shadows.
    public func abandon(_ sealed: SealedSubmission) {
        sealed.discard()
    }

    /// Throws when an attachment `renderPassDescriptor` supplies doesn't have the destination's pixel
    /// format. Attachments it leaves empty are the encoder's to make, and always match.
    private func validate(_ renderPassDescriptor: MTLRenderPassDescriptor, against destination: RenderDestination) throws {
        let colorAttachment = renderPassDescriptor.colorAttachments[0]
        if let expected = destination.colorPixelFormats.first, expected != .invalid {
            for texture in [colorAttachment?.texture, colorAttachment?.resolveTexture] {
                if let texture, texture.pixelFormat != expected {
                    throw SubmissionError.destinationMismatch(attachment: "color", expected: expected, found: texture.pixelFormat)
                }
            }
        }
        if destination.depthPixelFormat != .invalid {
            for texture in [renderPassDescriptor.depthAttachment.texture, renderPassDescriptor.depthAttachment.resolveTexture] {
                if let texture, texture.pixelFormat != destination.depthPixelFormat {
                    throw SubmissionError.destinationMismatch(attachment: "depth", expected: destination.depthPixelFormat, found: texture.pixelFormat)
                }
            }
        }
        if destination.stencilPixelFormat != .invalid, destination.depthPixelFormat != .depth32Float_stencil8 {
            for texture in [renderPassDescriptor.stencilAttachment.texture, renderPassDescriptor.stencilAttachment.resolveTexture] {
                if let texture, texture.pixelFormat != destination.stencilPixelFormat {
                    throw SubmissionError.destinationMismatch(attachment: "stencil", expected: destination.stencilPixelFormat, found: texture.pixelFormat)
                }
            }
        }
    }

    func prepare(builder submission: SubmissionBuilder, renderPassDescriptor inputDescriptor: MTLRenderPassDescriptor,
              scene: Object, viewMappings: [MTLVertexAmplificationViewMapping], preparationCommandBuffer: MTLCommandBuffer? = nil) throws -> [RecordedRenderPass] {
        guard !submission.isConsumed else { throw SubmissionError.alreadyDrawn }
        try validate(inputDescriptor, against: submission.destination)
        let renderPassDescriptor = inputDescriptor.privateCopy()
        preparedPasses.removeAll(keepingCapacity: true)
        preparingViews = submission.views

        let previousConfiguration = activeConfiguration
        activeConfiguration = submission.configuration
        defer { activeConfiguration = previousConfiguration }

        let recorder = submission.recorder
        let frame = submission.frame
        let commandBuffer = preparationCommandBuffer
        let cameras = submission.cameras
        let viewports = submission.viewports
        self.recorder = recorder
        defer {
            clearRouteEntries()
            self.recorder = nil
            preparedPasses.removeAll(keepingCapacity: true)
            preparingViews.removeAll(keepingCapacity: true)
        }

        let simd_viewports = submission.simdViewports
        RecordingProfile.begin(.updateAndTraversal)
        update(
            scene: scene,
            cameras: cameras,
            viewports: simd_viewports,
            recorder: recorder,
            encodingContext: commandBuffer.map { EncodingContext(commandBuffer: $0, frame: frame, views: submission.views, recorder: recorder) },
            lightOccurrences: submission.lightOccurrences
        )
        recorder.passBindings.bindsLights = !renderCollection.lightReceivers.isEmpty || submission.hasRecordedLightReceivers

        // The scene is one record: its shadows and colour passes share palette snapshots.
        recorder.beginRecord()
        // Every renderable takes its motion sample once, before any of its passes record.
        for collectedObject in renderCollection.objects {
            collectedObject.renderable?.beginOccurrence(frame: frame)
        }
        RecordingProfile.end()

        var arrayLength = 1
        for viewMapping in viewMappings {
            arrayLength = max(arrayLength, Int(viewMapping.renderTargetArrayIndexOffset) + 1)
        }

        // Every shadow drawn this frame records each caster once, for all their passes.
        if (!renderCollection.shadowCasters.isEmpty || !submission.shadowOccurrences.isEmpty),
           (!renderCollection.shadowReceivers.isEmpty || submission.hasRecordedShadowReceivers) {
            shadowsToDraw.removeAll(keepingCapacity: true)
            for light in renderCollection.lights where light.castShadow && light.shadow.shouldRender {
                shadowsToDraw.append(light.shadow)
            }
            preparedPasses.append(contentsOf: try shadowCasterRecording.prepare(shadowsToDraw, context: context,
                                                                           renderables: renderCollection.shadowCasters,
                                                                           occurrences: submission.shadowOccurrences, recorder: recorder))
            shadowsToDraw.removeAll(keepingCapacity: true)
        }

        updateDirectShadowTextures()
        updateProjectorTextures()
        recorder.passBindings.shadowTextures = directShadowTextures
        recorder.passBindings.projectorTextures = projectorTextures

        recordScene(recorder: recorder, views: submission.views)
        RecordingProfile.begin(.bookkeeping)
        buildRouteEntries(storage: recorder.storage)
        RecordingProfile.end()

        let inColorTexture = renderPassDescriptor.colorAttachments[0].texture
        let inColorResolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
        let inDepthTexture = renderPassDescriptor.depthAttachment.texture
        let inDepthResolveTexture = renderPassDescriptor.depthAttachment.resolveTexture
        let inStencilTexture = renderPassDescriptor.stencilAttachment.texture
        let inStencilResolveTexture = renderPassDescriptor.stencilAttachment.resolveTexture

        if colorPixelFormat == .invalid {
            renderPassDescriptor.colorAttachments[0].texture = nil
            renderPassDescriptor.colorAttachments[0].resolveTexture = nil
        } else {
            if context.sampleCount > 1 {
                if inColorTexture?.sampleCount != context.sampleCount {
                    setupColorMultisampleTexture(arrayLength: arrayLength)
                    renderPassDescriptor.colorAttachments[0].texture = colorMultisampleTexture
                }

                if inColorResolveTexture == nil {
                    setupColorTexture(arrayLength: arrayLength)
                    renderPassDescriptor.colorAttachments[0].resolveTexture = colorTexture
                    renderPassDescriptor.renderTargetWidth = colorTexture!.width
                    renderPassDescriptor.renderTargetHeight = colorTexture!.height
                }

            } else if inColorTexture == nil {
                setupColorTexture(arrayLength: arrayLength)
                renderPassDescriptor.colorAttachments[0].texture = colorTexture
                renderPassDescriptor.renderTargetWidth = colorTexture!.width
                renderPassDescriptor.renderTargetHeight = colorTexture!.height
            }
        }

        if depthPixelFormat == .invalid {
            renderPassDescriptor.depthAttachment.texture = nil
            renderPassDescriptor.depthAttachment.resolveTexture = nil
        } else {
            if context.sampleCount > 1 {
                if inDepthTexture?.sampleCount != context.sampleCount {
                    setupDepthMultisampleTexture(arrayLength: arrayLength)
                    renderPassDescriptor.depthAttachment.texture = depthMultisampleTexture
                }

                if inDepthResolveTexture == nil {
                    setupDepthTexture(arrayLength: arrayLength)
                    renderPassDescriptor.depthAttachment.resolveTexture = depthTexture
                }

            } else if inDepthTexture == nil {
                setupDepthTexture(arrayLength: arrayLength)
                renderPassDescriptor.depthAttachment.texture = depthTexture
            }

            if depthPixelFormat == .depth32Float_stencil8 {
                renderPassDescriptor.stencilAttachment.texture = depthTexture
            }
        }

        if stencilPixelFormat != .invalid, depthPixelFormat != .depth32Float_stencil8 {
            if stencilPixelFormat == .invalid {
                renderPassDescriptor.stencilAttachment.texture = nil
                renderPassDescriptor.stencilAttachment.resolveTexture = nil
            } else if context.sampleCount > 1 {
                if inStencilTexture?.sampleCount != context.sampleCount {
                    setupStencilMultisampleTexture(arrayLength: arrayLength)
                    renderPassDescriptor.stencilAttachment.texture = stencilMultisampleTexture
                }

                if inStencilResolveTexture == nil {
                    setupStencilTexture(arrayLength: arrayLength)
                    renderPassDescriptor.stencilAttachment.resolveTexture = stencilTexture
                }

            } else if inStencilTexture == nil {
                setupStencilTexture(arrayLength: arrayLength)
                renderPassDescriptor.stencilAttachment.texture = stencilTexture
            }
        }

        if context.sampleCount > 1 {
            if colorStoreAction == .store || colorStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.colorAttachments[0].storeAction = .storeAndMultisampleResolve
            } else {
                renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
            }
            if depthStoreAction == .store || depthStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.depthAttachment.storeAction = .storeAndMultisampleResolve
            } else {
                renderPassDescriptor.depthAttachment.storeAction = .multisampleResolve
            }
            if stencilPixelFormat != .invalid {
                if stencilStoreAction == .store || stencilStoreAction == .storeAndMultisampleResolve {
                    renderPassDescriptor.stencilAttachment.storeAction = .storeAndMultisampleResolve
                } else {
                    renderPassDescriptor.stencilAttachment.storeAction = .multisampleResolve
                }
            }
        } else {
            if colorStoreAction == .store || colorStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.colorAttachments[0].storeAction = .store
            } else {
                renderPassDescriptor.colorAttachments[0].storeAction = .dontCare
            }
            if depthStoreAction == .store || depthStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.depthAttachment.storeAction = .store
            } else {
                renderPassDescriptor.depthAttachment.storeAction = .dontCare
            }
            if stencilPixelFormat != .invalid {
                if stencilStoreAction == .store || stencilStoreAction == .storeAndMultisampleResolve {
                    renderPassDescriptor.stencilAttachment.storeAction = .store
                } else {
                    renderPassDescriptor.stencilAttachment.storeAction = .dontCare
                }
            }
        }

        renderPassDescriptor.colorAttachments[0].loadAction = colorLoadAction
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor

        renderPassDescriptor.depthAttachment.loadAction = depthLoadAction
        renderPassDescriptor.depthAttachment.clearDepth = clearDepth

        renderPassDescriptor.stencilAttachment.storeAction = stencilStoreAction
        renderPassDescriptor.stencilAttachment.loadAction = stencilLoadAction
        renderPassDescriptor.stencilAttachment.clearStencil = clearStencil

        let finalColorStoreAction = renderPassDescriptor.colorAttachments[0].storeAction
        let finalDepthStoreAction = renderPassDescriptor.depthAttachment.storeAction
        let finalStencilStoreAction = renderPassDescriptor.stencilAttachment.storeAction

        setupAuxiliaryTextures()

        _ = prepareMainRenderPasses(
            renderPassDescriptor: renderPassDescriptor,
            viewports: viewports,
            simdViewports: simd_viewports,
            viewMappings: viewMappings,
            finalColorStoreAction: finalColorStoreAction,
            finalDepthStoreAction: finalDepthStoreAction,
            finalStencilStoreAction: finalStencilStoreAction
        )
        try recorder.storage.resolveLightingPipelines(lightCount: renderCollection.lights.count,
                                                       shadowCount: directShadowLights.count,
                                                       shadowTextureCount: directShadowTextures.count,
                                                       projectorCount: projectorLights.count)
        return preparedPasses
    }

    private func normalizedOutputs(_ outputs: RendererOutputs) -> RendererOutputs {
        RendererOutputs(rawValue: outputs.rawValue | RendererOutputs.color.rawValue)
    }

    private var deferredRequiredOutputs: RendererOutputs {
        [.albedo, .normals, .pbr, .emissive]
    }

    private var requestedOutputs: RendererOutputs {
        var outputs = normalizedOutputs(activeOutputs)
        if renderingMode == .deferredGeometry {
            outputs.formUnion(deferredRequiredOutputs)
        }
        return outputs
    }

    private var requestedAuxiliaryOutputs: RendererOutputs {
        requestedOutputs.subtracting([.color])
    }

    private var usesAuxiliaryAttachments: Bool {
        renderingMode != .forward && !requestedAuxiliaryOutputs.isEmpty
    }

    private func materials(for renderable: Renderable) -> [Material] {
        if !renderable.materials.isEmpty {
            return renderable.materials
        }
        return [renderable.material].compactMap { $0 }
    }

    /// The routes `renderable` draws in, as bits of route raw values: a route when any of its
    /// materials draws in that route's pass, by the same decision its draw uses per submesh.
    private func routeMembership(of renderable: Renderable) -> Int {
        var membership = 0
        let materials = materials(for: renderable)
        for route in recordedRoutes {
            let materialPass = materialPass(for: Self.phase(for: route))
            for material in materials where materialPass.includes(material) {
                membership |= 1 << route.rawValue
                break
            }
        }
        return membership
    }

    /// The routes this encoder's rendering mode draws the scene in. The alpha-OIT route only when
    /// this encoder supports OIT, so its pass is never made otherwise.
    private var recordedRoutes: [RenderRoute] {
        if renderingMode == .forward {
            return supportsAlphaOit ? Self.forwardRoutes : Self.forwardRoutesWithoutAlphaOit
        }
        return supportsAlphaOit ? Self.layeredRoutes : Self.layeredRoutesWithoutAlphaOit
    }

    private static let forwardRoutes: [RenderRoute] = [.opaque, .alphaTransparent, .classicTransparent]
    private static let forwardRoutesWithoutAlphaOit: [RenderRoute] = [.opaque, .classicTransparent]
    private static let layeredRoutes: [RenderRoute] = [.surfaceOpaque, .unlitOpaque, .alphaTransparent, .classicTransparent]
    private static let layeredRoutesWithoutAlphaOit: [RenderRoute] = [.surfaceOpaque, .unlitOpaque, .classicTransparent]

    private static func phase(for route: RenderRoute) -> MaterialPassType {
        switch route {
        case .opaque: return .forwardOpaque
        case .surfaceOpaque: return .surfaceOpaque
        case .unlitOpaque: return .unlitOpaque
        case .alphaTransparent: return .alphaTransparent
        case .classicTransparent: return .classicTransparent
        }
    }

    /// Which of a renderable's materials draw in `phase`.
    private func materialPass(for phase: MaterialPassType) -> Renderable.MaterialPass {
        switch phase {
        case .forwardOpaque: return .opaque
        case .surfaceOpaque: return .surfaceOpaque
        case .unlitOpaque: return .unlitOpaque
        case .alphaTransparent: return .alphaTransparent
        case .classicTransparent: return .classicTransparent(excludesAlphaOit: supportsAlphaOit)
        }
    }

    /// Records the scene's colour passes: every collected renderable, once per route it draws in, in
    /// each layer's draw order (render order when sorting). Each recording is a render event with its
    /// own vertex uniforms; its packets are a run for that layer and route.
    private func recordScene(recorder: PacketRecorder, views: [RenderView]) {
        let routes = recordedRoutes
        let frusta = Self.frusta(of: views)
        for renderLayer in renderCollection.activeLayers {
            for renderable in renderCollection.renderables(renderLayer: renderLayer, sorted: sortObjects) {
                recordColorPasses(of: renderable, renderLayer: renderLayer, routes: routes, recorder: recorder, views: views, frusta: frusta, isRecorded: false)
            }
        }
    }

    /// The side planes of each of `views`, to cull against.
    private static func frusta(of views: [RenderView]) -> ContiguousArray<ViewFrustum> {
        var frusta = ContiguousArray<ViewFrustum>()
        frusta.reserveCapacity(views.count)
        for view in views {
            frusta.append(ViewFrustum(viewProjectionMatrix: view.viewProjectionMatrix))
        }
        return frusta
    }

    /// Whether `renderable` may be seen in any of `frusta`: always, when it isn't frustum culled.
    private static func mayBeSeen(_ renderable: Renderable, in frusta: ContiguousArray<ViewFrustum>) -> Bool {
        guard renderable.frustumCulled, !frusta.isEmpty else { return true }
        let bounds = renderable.worldBounds
        for frustum in frusta where frustum.mayContain(bounds) {
            return true
        }
        return false
    }

    /// Records `renderable` once per route of `routes` it draws in, as runs of its layer, unless it
    /// is outside every view.
    private func recordColorPasses(of renderable: Renderable, renderLayer: Int, routes: [RenderRoute], recorder: PacketRecorder, views: [RenderView], frusta: ContiguousArray<ViewFrustum>, isRecorded: Bool) {
        RecordingProfile.begin(.colourCulling)
        let mayBeSeen = Self.mayBeSeen(renderable, in: frusta)
        RecordingProfile.end()
        guard mayBeSeen else { return }
        let membership = routeMembership(of: renderable)
        for route in routes where membership & (1 << route.rawValue) != 0 {
            let phase = Self.phase(for: route)
            let packets = recorder.record(
                renderable,
                renderContext: renderContext(for: renderable, phase: phase),
                pass: .color,
                materialPass: materialPass(for: phase),
                views: views
            )
            RecordingProfile.begin(.bookkeeping)
            recorder.storage.appendRun(renderLayer: renderLayer, routeIndex: route.rawValue, packets: packets, isRecorded: isRecorded)
            RecordingProfile.end()
        }
    }

    /// Records `scene` as it is now into `submission`: each visible renderable is an occurrence of
    /// its own, recorded in the colour routes from the submission's views, in render order within
    /// each layer when sorting.
    func record(scene: Object, into submission: SubmissionBuilder) throws {
        let previousConfiguration = activeConfiguration
        activeConfiguration = submission.configuration
        defer { activeConfiguration = previousConfiguration }

        let recorder = submission.recorder
        recorder.defersLightingPipelines = true
        recorder.beginRecord()

        renderCollection.reset()
        sceneTraversal.collect(scene: scene, into: renderCollection)
        updateScene(cameras: submission.cameras, viewports: submission.simdViewports,
                    recorder: recorder, encodingContext: nil, runsMaterialUpdates: false)
        for (index, light) in renderCollection.lights.enumerated() {
            let identity = RecordedLightIdentity(record: recorder.recordToken, occurrenceIndex: index)
            submission.lightOccurrences.append(try RecordedLightOccurrence(light, identity: identity))
        }
        submission.hasRecordedShadowReceivers = submission.hasRecordedShadowReceivers || !renderCollection.shadowReceivers.isEmpty
        submission.hasRecordedLightReceivers = submission.hasRecordedLightReceivers || !renderCollection.lightReceivers.isEmpty
        recordedRenderables.removeAll(keepingCapacity: true)
        for object in renderCollection.objects {
            if let renderable = object.renderable { recordedRenderables.append(renderable) }
        }
        if sortObjects {
            // Stable: equal render orders keep the scene's order.
            RecordingProfile.begin(.bookkeeping)
            recordedRenderables.sort { $0.renderOrder < $1.renderOrder }
            RecordingProfile.end()
        }

        let routes = recordedRoutes
        let frusta = Self.frusta(of: submission.views)
        for renderable in recordedRenderables {
            renderable.beginOccurrence(frame: recorder.frame)
            if renderable.castShadow {
                let packets = recorder.record(renderable, renderContext: context, pass: .shadow,
                                               materialPass: .all, views: submission.views)
                if !packets.isEmpty {
                    submission.shadowOccurrences.append(RecordedShadowOccurrence(packets: packets,
                                                                                  occurrence: renderable.occurrence,
                                                                                  bounds: renderable.worldBounds,
                                                                                  frustumCulled: renderable.frustumCulled))
                }
            }
            recordColorPasses(of: renderable, renderLayer: renderable.renderLayer.rawValue, routes: routes, recorder: recorder, views: submission.views, frusta: frusta, isRecorded: true)
        }
        recordedRenderables.removeAll(keepingCapacity: true)
    }

    /// Fills each route's buckets from the draw's runs, per layer: the scene's own packets, then the
    /// records', in recorded order, and the route's entries from them.
    private func buildRouteEntries(storage: PacketStorage) {
        passLayers.removeAll(keepingCapacity: true)
        for run in storage.runs where !passLayers.contains(run.renderLayer) {
            let insertionIndex = passLayers.firstIndex { $0 > run.renderLayer } ?? passLayers.count
            passLayers.insert(run.renderLayer, at: insertionIndex)
        }

        for routeIndex in packetBuckets.indices {
            if packetBuckets[routeIndex].count < passLayers.count {
                packetBuckets[routeIndex].append(contentsOf: repeatElement([], count: passLayers.count - packetBuckets[routeIndex].count))
            }
            for pass in packetBuckets[routeIndex].indices {
                packetBuckets[routeIndex][pass].removeAll(keepingCapacity: true)
            }
        }

        for run in storage.runs where !run.isRecorded {
            appendRunToBucket(run)
        }
        for run in storage.runs where run.isRecorded {
            appendRunToBucket(run)
        }

        let ordersRecordedScenes = sortObjects && storage.runs.contains(where: \.isRecorded)
        for routeIndex in routeEntries.indices {
            for pass in passLayers.indices where !packetBuckets[routeIndex][pass].isEmpty {
                if ordersRecordedScenes {
                    packetBuckets[routeIndex][pass].sort {
                        storage.renderOrder(ofPacketAt: $0) < storage.renderOrder(ofPacketAt: $1)
                    }
                }
                routeEntries[routeIndex].append(RenderRouteEntry(pass: pass, packets: packetBuckets[routeIndex][pass][...]))
            }
        }
    }

    private func appendRunToBucket(_ run: PacketTables.PacketRun) {
        guard let pass = passLayers.firstIndex(of: run.renderLayer) else { return }
        packetBuckets[run.routeIndex][pass].append(contentsOf: run.packets)
    }

    /// Entries hold slices of the buckets: cleared first, so the buckets are cleared in place.
    private func clearRouteEntries() {
        for routeIndex in routeEntries.indices {
            routeEntries[routeIndex].removeAll(keepingCapacity: true)
        }
    }

    private func routePassEntries(route: RenderRoute) -> [RenderRouteEntry] {
        routeEntries[route.rawValue]
    }

    private func supportedOutputs(for renderable: Renderable, phase: MaterialPassType) -> RendererOutputs {
        switch phase {
        case .forwardOpaque, .alphaTransparent, .classicTransparent, .unlitOpaque:
            return [.color]
        case .surfaceOpaque:
            var outputs: RendererOutputs = [.color]
            for material in materials(for: renderable)
                where material.lightingModel == .surface && material.blending == .disabled
            {
                outputs.formUnion(material.supportedOutputs.intersection(requestedOutputs))
            }
            return normalizedOutputs(outputs)
        }
    }

    private func renderContext(for renderable: Renderable, phase: MaterialPassType) -> Context {
        let mode: RenderingMode = phase == .surfaceOpaque ? renderingMode : .forward
        let alphaOitEnabled = phase == .alphaTransparent
        let outputs = supportedOutputs(for: renderable, phase: phase)
        let slot = (Self.renderingModeIndex(mode) * Self.renderContextPassTypes + phase.rawValue) * Self.renderContextOutputSets + outputs.rawValue
        if slot < renderContexts.count, let renderContext = renderContexts[slot] {
            return renderContext
        }

        let renderContext = Context(
            device: context.device,
            sampleCount: context.sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat,
            vertexAmplificationCount: context.vertexAmplificationCount,
            maxBuffersInFlight: context.maxBuffersInFlight,
            renderingMode: mode,
            activeOutputs: outputs,
            alphaOitEnabled: alphaOitEnabled,
            albedoPixelFormat: context.albedoPixelFormat,
            normalsPixelFormat: context.normalsPixelFormat,
            pbrPixelFormat: context.pbrPixelFormat,
            velocityPixelFormat: context.velocityPixelFormat,
            emissivePixelFormat: context.emissivePixelFormat
        )

        if slot >= renderContexts.count {
            renderContexts.append(contentsOf: repeatElement(nil, count: slot + 1 - renderContexts.count))
        }
        renderContexts[slot] = renderContext
        return renderContext
    }

    private func setupAuxiliaryTextures() {
        if usesAuxiliaryAttachments {
            precondition(
                context.sampleCount == 1,
                "Satin RenderEncoder auxiliary MRT outputs currently require sampleCount == 1."
            )
        }

        if requestedAuxiliaryOutputs.contains(.albedo) {
            setupAlbedoTexture()
        } else {
            albedoTexture = nil
            updateAlbedoTexture = true
        }

        if requestedAuxiliaryOutputs.contains(.normals) {
            setupNormalTexture()
        } else {
            normalTexture = nil
            updateNormalTexture = true
        }

        if requestedAuxiliaryOutputs.contains(.pbr) {
            setupPBRTexture()
        } else {
            pbrTexture = nil
            updatePBRTexture = true
        }

        if requestedAuxiliaryOutputs.contains(.velocity) {
            setupVelocityTexture()
        } else {
            velocityTexture = nil
            updateVelocityTexture = true
        }

        if requestedAuxiliaryOutputs.contains(.emissive) {
            setupEmissiveTexture()
        } else {
            emissiveTexture = nil
            updateEmissiveTexture = true
        }
    }

    private func configureMainAttachments(
        renderPassDescriptor: MTLRenderPassDescriptor,
        colorLoadAction: MTLLoadAction,
        depthLoadAction: MTLLoadAction,
        stencilLoadAction: MTLLoadAction,
        colorStoreAction: MTLStoreAction,
        depthStoreAction: MTLStoreAction,
        stencilStoreAction: MTLStoreAction
    ) {
        renderPassDescriptor.colorAttachments[0].loadAction = colorLoadAction
        renderPassDescriptor.colorAttachments[0].storeAction = colorStoreAction
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor

        renderPassDescriptor.depthAttachment.loadAction = depthLoadAction
        renderPassDescriptor.depthAttachment.storeAction = depthStoreAction
        renderPassDescriptor.depthAttachment.clearDepth = clearDepth

        renderPassDescriptor.stencilAttachment.loadAction = stencilLoadAction
        renderPassDescriptor.stencilAttachment.storeAction = stencilStoreAction
        renderPassDescriptor.stencilAttachment.clearStencil = clearStencil
    }

    @discardableResult
    private func configureAuxiliaryAttachments(
        renderPassDescriptor: MTLRenderPassDescriptor,
        enabled: Bool = true
    ) -> [Int] {
        let auxiliaryAttachments: [(Int, RendererOutputs, MTLTexture?)] = [
            (1, .albedo, albedoTexture),
            (2, .normals, normalTexture),
            (3, .pbr, pbrTexture),
            (4, .velocity, velocityTexture),
            (5, .emissive, emissiveTexture),
        ]

        var activeAttachmentIndices = [Int]()

        for (index, flag, texture) in auxiliaryAttachments {
            guard let attachment = colorAttachment(renderPassDescriptor, index: index) else { continue }
            if enabled, requestedAuxiliaryOutputs.contains(flag), let texture {
                attachment.texture = texture
                attachment.resolveTexture = nil
                attachment.loadAction = .clear
                attachment.storeAction = .store
                attachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
                activeAttachmentIndices.append(index)
            } else {
                attachment.texture = nil
                attachment.resolveTexture = nil
                attachment.loadAction = .dontCare
                attachment.storeAction = .dontCare
                attachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
            }
        }

        return activeAttachmentIndices
    }

    private func prepareDeferredLightingMaterial(view: RenderView) {
        deferredLightingMaterial.albedoTexture = albedoTexture
        deferredLightingMaterial.normalTexture = normalTexture
        deferredLightingMaterial.pbrTexture = pbrTexture
        deferredLightingMaterial.emissiveTexture = emissiveTexture
        deferredLightingMaterial.depthTexture = depthTexture

        deferredLightingMaterial.lightCount = renderCollection.lights.count
        deferredLightingMaterial.projectorCount = projectorLights.count
        deferredLightingMaterial.directShadowCount = directShadowLights.count
        deferredLightingMaterial.directShadowTextureCount = directShadowTextures.count

        deferredLightingMaterial.environmentIntensity = activeEnvironmentIntensity
        deferredLightingMaterial.reflectionTexcoordTransform = simd_float4x4(
            textureTransform: activeReflectionTexcoordTransform
        )
        deferredLightingMaterial.irradianceTexcoordTransform = simd_float4x4(
            textureTransform: activeIrradianceTexcoordTransform
        )
        deferredLightingMaterial.reflectionTexture = activeReflectionTexture
        deferredLightingMaterial.irradianceTexture = activeIrradianceTexture
        deferredLightingMaterial.brdfTexture = activeBrdfTexture
        deferredLightingMaterial.inverseProjectionMatrix = view.projectionMatrix.inverse
        deferredLightingMaterial.inverseViewMatrix = view.viewMatrix.inverse
        deferredLightingMaterial.worldCameraPosition = simd_float4(view.worldPosition, 1)
    }

    @discardableResult
    private func prepareDeferredLightingPass(
        renderPassDescriptor: MTLRenderPassDescriptor,
        sceneView: RenderView?,
        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        colorStoreAction: MTLStoreAction,
        unlitEntries: [RenderRouteEntry] = [],
        finalDepthStoreAction: MTLStoreAction = .dontCare,
        finalStencilStoreAction: MTLStoreAction = .dontCare
    ) -> Bool {
        guard albedoTexture != nil,
              normalTexture != nil,
              pbrTexture != nil,
              emissiveTexture != nil,
              depthTexture != nil
        else { return false }

        guard let sceneView else { return false }
        prepareDeferredLightingMaterial(view: sceneView)
        deferredLightingCamera.update()
        deferredLightingMesh.update()

        let savedDepthTexture = renderPassDescriptor.depthAttachment.texture
        let savedDepthResolveTexture = renderPassDescriptor.depthAttachment.resolveTexture
        let savedStencilTexture = renderPassDescriptor.stencilAttachment.texture
        let savedStencilResolveTexture = renderPassDescriptor.stencilAttachment.resolveTexture

        defer {
            renderPassDescriptor.depthAttachment.texture = savedDepthTexture
            renderPassDescriptor.depthAttachment.resolveTexture = savedDepthResolveTexture
            renderPassDescriptor.stencilAttachment.texture = savedStencilTexture
            renderPassDescriptor.stencilAttachment.resolveTexture = savedStencilResolveTexture
        }

        let hasUnlit = !unlitEntries.isEmpty
        let multipleUnlitPasses = unlitEntries.count > 1

        // When unlit objects follow in the same encoder, load depth/stencil so they can depth-test
        // against the geometry pass result. Without unlit objects, dontCare avoids unnecessary loads.
        configureMainAttachments(
            renderPassDescriptor: renderPassDescriptor,
            colorLoadAction: .clear,
            depthLoadAction: hasUnlit ? .load : .dontCare,
            stencilLoadAction: hasUnlit ? .load : .dontCare,
            colorStoreAction: multipleUnlitPasses ? .store : colorStoreAction,
            depthStoreAction: hasUnlit ? (multipleUnlitPasses ? .store : finalDepthStoreAction) : .dontCare,
            stencilStoreAction: hasUnlit ? (multipleUnlitPasses ? .store : finalStencilStoreAction) : .dontCare
        )
        configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)

        let resolve = appendPreparedPass(renderPassDescriptor, label: "\(label) Deferred Lighting Resolve", viewports: viewports, viewMappings: viewMappings)
        if let recorder {
            let lightingViews = (0 ..< max(context.vertexAmplificationCount, 1)).map { index in
                RenderView(camera: deferredLightingCamera, viewport: simdViewports.isEmpty ? .zero : simdViewports[min(index, simdViewports.count - 1)], frame: recorder.frame)
            }
            deferredLightingMesh.beginOccurrence(frame: recorder.frame)
            let packets = recorder.record(deferredLightingMesh, renderContext: renderContext(for: deferredLightingMesh, phase: .unlitOpaque), pass: .color, materialPass: materialPass(for: .unlitOpaque), views: lightingViews)
            preparedPasses[resolve].commands.append(.range(packets, viewIndex: 0))
        }
        if let entry = unlitEntries.first { preparedPasses[resolve].commands.append(.indices(entry.packets, viewIndex: 0)) }
        for (index, entry) in unlitEntries.dropFirst().enumerated() {
            let final = index == unlitEntries.count - 2
            renderPassDescriptor.colorAttachments[0].loadAction = .load
            renderPassDescriptor.depthAttachment.loadAction = .load
            renderPassDescriptor.stencilAttachment.loadAction = .load
            renderPassDescriptor.colorAttachments[0].storeAction = final ? colorStoreAction : .store
            renderPassDescriptor.depthAttachment.storeAction = final ? finalDepthStoreAction : .store
            renderPassDescriptor.stencilAttachment.storeAction = final ? finalStencilStoreAction : .store
            let pass = appendPreparedPass(renderPassDescriptor, label: "\(label) Unlit Forward Pass \(entry.pass)", viewports: viewports, viewMappings: viewMappings)
            preparedPasses[pass].commands.append(.indices(entry.packets, viewIndex: 0))
        }

        return true
    }

    private func needsClearPass(renderPassDescriptor: MTLRenderPassDescriptor, auxiliaryAttachmentIndices: [Int]) -> Bool {
        if renderPassDescriptor.colorAttachments[0].texture != nil,
           renderPassDescriptor.colorAttachments[0].loadAction == .clear
        {
            return true
        }

        if renderPassDescriptor.depthAttachment.texture != nil,
           renderPassDescriptor.depthAttachment.loadAction == .clear
        {
            return true
        }

        if renderPassDescriptor.stencilAttachment.texture != nil,
           renderPassDescriptor.stencilAttachment.loadAction == .clear
        {
            return true
        }

        for index in auxiliaryAttachmentIndices {
            guard let attachment = colorAttachment(renderPassDescriptor, index: index) else { continue }
            if attachment.texture != nil, attachment.loadAction == .clear {
                return true
            }
        }

        return false
    }

    private func prepareAlphaOitPassDescriptor(
        _ renderPassDescriptor: MTLRenderPassDescriptor,
        imageblockSampleLength: Int,
        colorLoadAction: MTLLoadAction,
        depthLoadAction: MTLLoadAction,
        stencilLoadAction: MTLLoadAction,
        colorStoreAction: MTLStoreAction,
        depthStoreAction: MTLStoreAction,
        stencilStoreAction: MTLStoreAction
    ) throws {
        configureMainAttachments(
            renderPassDescriptor: renderPassDescriptor,
            colorLoadAction: colorLoadAction,
            depthLoadAction: depthLoadAction,
            stencilLoadAction: stencilLoadAction,
            colorStoreAction: colorStoreAction,
            depthStoreAction: depthStoreAction,
            stencilStoreAction: stencilStoreAction
        )
        configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
        renderPassDescriptor.tileWidth = alphaOitTileSize.width
        renderPassDescriptor.tileHeight = alphaOitTileSize.height
        renderPassDescriptor.imageblockSampleLength = imageblockSampleLength
    }

    private func alphaOitImageblockSampleLength(for routeEntries: [RenderRouteEntry]) -> Int? {
        if let recorder {
            for entry in routeEntries {
                if let packetIndex = entry.packets.first {
                    return recorder.storage.pipeline(ofPacketAt: packetIndex).imageblockSampleLength
                }
            }
        }
        return nil
    }

    @discardableResult
    private func prepareAlphaOitRoute(
        renderPassDescriptor: MTLRenderPassDescriptor,
        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        clearWhenEmpty: Bool,
        colorLoadAction: MTLLoadAction,
        depthLoadAction: MTLLoadAction,
        stencilLoadAction: MTLLoadAction,
        colorStoreAction: MTLStoreAction,
        depthStoreAction: MTLStoreAction,
        stencilStoreAction: MTLStoreAction
    ) -> Bool {
        let routeEntries = routePassEntries(route: .alphaTransparent)
        let shouldEncode = !routeEntries.isEmpty || clearWhenEmpty
        guard shouldEncode else { return false }

        do {
            let resources = try alphaOitResources.load()
            guard let imageblockSampleLength = alphaOitImageblockSampleLength(for: routeEntries) else {
                return false
            }
            try prepareAlphaOitPassDescriptor(
                renderPassDescriptor,
                imageblockSampleLength: imageblockSampleLength,
                colorLoadAction: colorLoadAction,
                depthLoadAction: depthLoadAction,
                stencilLoadAction: stencilLoadAction,
                colorStoreAction: colorStoreAction,
                depthStoreAction: depthStoreAction,
                stencilStoreAction: stencilStoreAction
            )

            let pass = appendPreparedPass(renderPassDescriptor, label: "\(label) Alpha OIT Pass", viewports: viewports, viewMappings: viewMappings)
            preparedPasses[pass].commands.append(.tileClear(resources.tilePipeline, alphaOitTileSize))
            for (index, group) in alphaOitGroups(for: routeEntries).enumerated() {
                if index > 0 {
                    preparedPasses[pass].commands.append(.tileBlend(resources.blendPipeline, resources.blendDepthStencilState))
                    preparedPasses[pass].commands.append(.tileClear(resources.tilePipeline, alphaOitTileSize))
                }
                preparedPasses[pass].commands.append(.indices(group.packets, viewIndex: 0))
            }
            preparedPasses[pass].commands.append(.tileBlend(resources.blendPipeline, resources.blendDepthStencilState))

            return true
        } catch {
            print("\(label) Alpha OIT: \(error.localizedDescription)")
            return false
        }
    }

    // Image-block OIT blends every fragment it accumulates order-independently, so draw order
    // inside one accumulation is lost. Splitting the route into groups, each accumulated and
    // resolved on its own, keeps ordering between groups: a group always composites over the
    // groups before it. Groups split on render layer, and on render order when sortObjects is
    // enabled. Renderables sharing a render layer and render order still blend order-independently.
    // A layer's recorded scenes follow its own, so a split never mixes them out of order.
    private func alphaOitGroups(for routeEntries: [RenderRouteEntry]) -> [RenderRouteEntry] {
        var groups: [RenderRouteEntry] = []

        guard let recorder else { return routeEntries }
        for entry in routeEntries {
            var groupStart = entry.packets.startIndex
            for packetPosition in entry.packets.indices where packetPosition > groupStart {
                let renderOrder = recorder.storage.renderOrder(ofPacketAt: entry.packets[packetPosition])
                let previousRenderOrder = recorder.storage.renderOrder(ofPacketAt: entry.packets[packetPosition - 1])
                if sortObjects, renderOrder != previousRenderOrder {
                    groups.append(RenderRouteEntry(pass: entry.pass, packets: entry.packets[groupStart ..< packetPosition]))
                    groupStart = packetPosition
                }
            }

            groups.append(RenderRouteEntry(pass: entry.pass, packets: entry.packets[groupStart ..< entry.packets.endIndex]))
        }

        return groups
    }

    @discardableResult
    private func prepareRouteEntries(
        renderPassDescriptor: MTLRenderPassDescriptor,
        entries: [RenderRouteEntry],
        phase: MaterialPassType,
        label: String,

        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        clearWhenEmpty: Bool
    ) -> Bool {
        return prepareEntries(renderPassDescriptor, entries: entries, label: label, viewports: viewports, viewMappings: viewMappings, auxiliaryAttachmentIndices: [], clearWhenEmpty: clearWhenEmpty)
    }

    @discardableResult
    private func prepareRoute(
        renderPassDescriptor: MTLRenderPassDescriptor,
        route: RenderRoute,
        phase: MaterialPassType,
        label: String,

        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        auxiliaryAttachmentIndices: [Int],
        clearWhenEmpty: Bool
    ) -> Bool {
        return prepareEntries(renderPassDescriptor, entries: routePassEntries(route: route), label: label, viewports: viewports, viewMappings: viewMappings,
                              auxiliaryAttachmentIndices: auxiliaryAttachmentIndices,
                              clearWhenEmpty: clearWhenEmpty && needsClearPass(renderPassDescriptor: renderPassDescriptor, auxiliaryAttachmentIndices: auxiliaryAttachmentIndices))
    }

    @discardableResult
    private func prepareMainRenderPasses(
        renderPassDescriptor: MTLRenderPassDescriptor,
        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        finalColorStoreAction: MTLStoreAction,
        finalDepthStoreAction: MTLStoreAction,
        finalStencilStoreAction: MTLStoreAction
    ) -> Bool {
        let hasAlphaTransparentRenderables = !routePassEntries(route: .alphaTransparent).isEmpty
        let hasClassicTransparentRenderables = !routePassEntries(route: .classicTransparent).isEmpty
        let hasTransparentRenderables = hasAlphaTransparentRenderables || hasClassicTransparentRenderables
        let hasSurfaceOpaqueRenderables = !routePassEntries(route: .surfaceOpaque).isEmpty
        let hasUnlitOpaqueRenderables = !routePassEntries(route: .unlitOpaque).isEmpty
        switch renderingMode {
        case .forward:
            configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
            let opaqueEncoded = prepareRoute(
                renderPassDescriptor: renderPassDescriptor,

                route: .opaque,
                phase: .forwardOpaque,
                label: "Forward Opaque",

                viewports: viewports,
                simdViewports: simdViewports,
                viewMappings: viewMappings,
                auxiliaryAttachmentIndices: [],
                clearWhenEmpty: !hasTransparentRenderables
            )

            var didEncode = opaqueEncoded

            if hasAlphaTransparentRenderables {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: didEncode ? .load : colorLoadAction,
                    depthLoadAction: didEncode ? .load : depthLoadAction,
                    stencilLoadAction: didEncode ? .load : stencilLoadAction,
                    colorStoreAction: hasClassicTransparentRenderables ? .store : finalColorStoreAction,
                    depthStoreAction: hasClassicTransparentRenderables ? .store : finalDepthStoreAction,
                    stencilStoreAction: hasClassicTransparentRenderables ? .store : finalStencilStoreAction
                )
                let alphaEncoded = prepareAlphaOitRoute(
                    renderPassDescriptor: renderPassDescriptor,

                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    clearWhenEmpty: !didEncode,
                    colorLoadAction: didEncode ? .load : colorLoadAction,
                    depthLoadAction: didEncode ? .load : depthLoadAction,
                    stencilLoadAction: didEncode ? .load : stencilLoadAction,
                    colorStoreAction: hasClassicTransparentRenderables ? .store : finalColorStoreAction,
                    depthStoreAction: hasClassicTransparentRenderables ? .store : finalDepthStoreAction,
                    stencilStoreAction: hasClassicTransparentRenderables ? .store : finalStencilStoreAction
                )
                didEncode = didEncode || alphaEncoded
            }

            if hasClassicTransparentRenderables {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: didEncode ? .load : colorLoadAction,
                    depthLoadAction: didEncode ? .load : depthLoadAction,
                    stencilLoadAction: didEncode ? .load : stencilLoadAction,
                    colorStoreAction: finalColorStoreAction,
                    depthStoreAction: finalDepthStoreAction,
                    stencilStoreAction: finalStencilStoreAction
                )
                let transparentEncoded = prepareRoute(
                    renderPassDescriptor: renderPassDescriptor,

                    route: .classicTransparent,
                    phase: .classicTransparent,
                    label: "Classic Transparent Forward",

                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    auxiliaryAttachmentIndices: [],
                    clearWhenEmpty: !didEncode
                )
                didEncode = didEncode || transparentEncoded
            }

            return didEncode

        case .forwardPlus:
            let needsSurfacePass = hasSurfaceOpaqueRenderables || usesAuxiliaryAttachments || (!hasUnlitOpaqueRenderables && !hasTransparentRenderables && renderCollection.isEmpty)
            var didEncode = false

            if needsSurfacePass {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: colorLoadAction,
                    depthLoadAction: depthLoadAction,
                    stencilLoadAction: stencilLoadAction,
                    colorStoreAction: (hasUnlitOpaqueRenderables || hasTransparentRenderables) ? .store : finalColorStoreAction,
                    depthStoreAction: (hasUnlitOpaqueRenderables || hasTransparentRenderables) ? .store : finalDepthStoreAction,
                    stencilStoreAction: (hasUnlitOpaqueRenderables || hasTransparentRenderables) ? .store : finalStencilStoreAction
                )
                let auxiliaryAttachmentIndices = configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor)
                didEncode = prepareRoute(
                    renderPassDescriptor: renderPassDescriptor,

                    route: .surfaceOpaque,
                    phase: .surfaceOpaque,
                    label: "Surface MRT",

                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    auxiliaryAttachmentIndices: auxiliaryAttachmentIndices,
                    clearWhenEmpty: true
                )
            } else {
                configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
            }

            if hasUnlitOpaqueRenderables {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: needsSurfacePass ? .load : colorLoadAction,
                    depthLoadAction: needsSurfacePass ? .load : depthLoadAction,
                    stencilLoadAction: needsSurfacePass ? .load : stencilLoadAction,
                    colorStoreAction: hasTransparentRenderables ? .store : finalColorStoreAction,
                    depthStoreAction: hasTransparentRenderables ? .store : finalDepthStoreAction,
                    stencilStoreAction: hasTransparentRenderables ? .store : finalStencilStoreAction
                )
                configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
                let unlitEncoded = prepareRoute(
                    renderPassDescriptor: renderPassDescriptor,

                    route: .unlitOpaque,
                    phase: .unlitOpaque,
                    label: "Opaque Unlit Forward",

                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    auxiliaryAttachmentIndices: [],
                    clearWhenEmpty: !didEncode
                )
                didEncode = didEncode || unlitEncoded
            }

            if hasTransparentRenderables {
                if hasAlphaTransparentRenderables {
                    configureMainAttachments(
                        renderPassDescriptor: renderPassDescriptor,
                        colorLoadAction: didEncode ? .load : colorLoadAction,
                        depthLoadAction: didEncode ? .load : depthLoadAction,
                        stencilLoadAction: didEncode ? .load : stencilLoadAction,
                        colorStoreAction: hasClassicTransparentRenderables ? .store : finalColorStoreAction,
                        depthStoreAction: hasClassicTransparentRenderables ? .store : finalDepthStoreAction,
                        stencilStoreAction: hasClassicTransparentRenderables ? .store : finalStencilStoreAction
                    )
                    let alphaEncoded = prepareAlphaOitRoute(
                        renderPassDescriptor: renderPassDescriptor,

                        viewports: viewports,
                        simdViewports: simdViewports,
                        viewMappings: viewMappings,
                        clearWhenEmpty: !didEncode,
                        colorLoadAction: didEncode ? .load : colorLoadAction,
                        depthLoadAction: didEncode ? .load : depthLoadAction,
                        stencilLoadAction: didEncode ? .load : stencilLoadAction,
                        colorStoreAction: hasClassicTransparentRenderables ? .store : finalColorStoreAction,
                        depthStoreAction: hasClassicTransparentRenderables ? .store : finalDepthStoreAction,
                        stencilStoreAction: hasClassicTransparentRenderables ? .store : finalStencilStoreAction
                    )
                    didEncode = didEncode || alphaEncoded
                }

                if hasClassicTransparentRenderables {
                    configureMainAttachments(
                        renderPassDescriptor: renderPassDescriptor,
                        colorLoadAction: didEncode ? .load : colorLoadAction,
                        depthLoadAction: didEncode ? .load : depthLoadAction,
                        stencilLoadAction: didEncode ? .load : stencilLoadAction,
                        colorStoreAction: finalColorStoreAction,
                        depthStoreAction: finalDepthStoreAction,
                        stencilStoreAction: finalStencilStoreAction
                    )
                    configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
                    let transparentEncoded = prepareRoute(
                        renderPassDescriptor: renderPassDescriptor,

                        route: .classicTransparent,
                        phase: .classicTransparent,
                        label: "Classic Transparent Forward",

                        viewports: viewports,
                        simdViewports: simdViewports,
                        viewMappings: viewMappings,
                        auxiliaryAttachmentIndices: [],
                        clearWhenEmpty: !didEncode
                    )
                    didEncode = didEncode || transparentEncoded
                }
            }

            if !didEncode {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: colorLoadAction,
                    depthLoadAction: depthLoadAction,
                    stencilLoadAction: stencilLoadAction,
                    colorStoreAction: finalColorStoreAction,
                    depthStoreAction: finalDepthStoreAction,
                    stencilStoreAction: finalStencilStoreAction
                )
                configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
                return prepareRoute(
                    renderPassDescriptor: renderPassDescriptor,

                    route: .surfaceOpaque,
                    phase: .surfaceOpaque,
                    label: "Empty",

                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    auxiliaryAttachmentIndices: [],
                    clearWhenEmpty: true
                )
            }

            return didEncode

        case .deferredGeometry:
            let opaqueUnlitEntries = routePassEntries(route: .unlitOpaque)
            let needsSurfacePass = hasSurfaceOpaqueRenderables || usesAuxiliaryAttachments || (opaqueUnlitEntries.isEmpty && !hasTransparentRenderables && renderCollection.isEmpty)
            var didEncode = false

            if needsSurfacePass {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: colorLoadAction,
                    depthLoadAction: depthLoadAction,
                    stencilLoadAction: stencilLoadAction,
                    colorStoreAction: .dontCare,
                    depthStoreAction: .store,
                    stencilStoreAction: (opaqueUnlitEntries.isEmpty && !hasTransparentRenderables) ? finalStencilStoreAction : .store
                )
                let auxiliaryAttachmentIndices = configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor)
                let surfaceEncoded = prepareRoute(
                    renderPassDescriptor: renderPassDescriptor,

                    route: .surfaceOpaque,
                    phase: .surfaceOpaque,
                    label: "Deferred Geometry",

                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    auxiliaryAttachmentIndices: auxiliaryAttachmentIndices,
                    clearWhenEmpty: true
                )
                let resolveEncoded = prepareDeferredLightingPass(
                    renderPassDescriptor: renderPassDescriptor,

                    sceneView: preparingViews.first,
                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    colorStoreAction: hasTransparentRenderables ? .store : finalColorStoreAction,
                    unlitEntries: opaqueUnlitEntries,
                    finalDepthStoreAction: hasTransparentRenderables ? .store : finalDepthStoreAction,
                    finalStencilStoreAction: hasTransparentRenderables ? .store : finalStencilStoreAction
                )
                didEncode = surfaceEncoded || resolveEncoded

                // G-buffer textures weren't available (prepareDeferredLightingPass returned false)
                // but unlit geometry (e.g. skybox) still needs to render. Fall back to a plain
                // forward unlit pass so these objects are never silently dropped.
                if !resolveEncoded, !opaqueUnlitEntries.isEmpty {
                    configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
                    configureMainAttachments(
                        renderPassDescriptor: renderPassDescriptor,
                        colorLoadAction: didEncode ? .load : colorLoadAction,
                        depthLoadAction: didEncode ? .load : depthLoadAction,
                        stencilLoadAction: didEncode ? .load : stencilLoadAction,
                        colorStoreAction: hasTransparentRenderables ? .store : finalColorStoreAction,
                        depthStoreAction: hasTransparentRenderables ? .store : finalDepthStoreAction,
                        stencilStoreAction: hasTransparentRenderables ? .store : finalStencilStoreAction
                    )
                    let unlitFallbackEncoded = prepareRoute(
                        renderPassDescriptor: renderPassDescriptor,

                        route: .unlitOpaque,
                        phase: .unlitOpaque,
                        label: "Opaque Unlit Fallback",

                        viewports: viewports,
                        simdViewports: simdViewports,
                        viewMappings: viewMappings,
                        auxiliaryAttachmentIndices: [],
                        clearWhenEmpty: !didEncode
                    )
                    didEncode = didEncode || unlitFallbackEncoded
                }
            } else {
                configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)

                // No surface/geometry pass but unlit objects still need to be rendered.
                if !opaqueUnlitEntries.isEmpty {
                    configureMainAttachments(
                        renderPassDescriptor: renderPassDescriptor,
                        colorLoadAction: colorLoadAction,
                        depthLoadAction: depthLoadAction,
                        stencilLoadAction: stencilLoadAction,
                        colorStoreAction: hasTransparentRenderables ? .store : finalColorStoreAction,
                        depthStoreAction: hasTransparentRenderables ? .store : finalDepthStoreAction,
                        stencilStoreAction: hasTransparentRenderables ? .store : finalStencilStoreAction
                    )
                    let unlitEncoded = prepareRoute(
                        renderPassDescriptor: renderPassDescriptor,

                        route: .unlitOpaque,
                        phase: .unlitOpaque,
                        label: "Opaque Unlit Forward",

                        viewports: viewports,
                        simdViewports: simdViewports,
                        viewMappings: viewMappings,
                        auxiliaryAttachmentIndices: [],
                        clearWhenEmpty: true
                    )
                    didEncode = unlitEncoded
                }
            }

            if hasTransparentRenderables {
                if hasAlphaTransparentRenderables {
                    configureMainAttachments(
                        renderPassDescriptor: renderPassDescriptor,
                        colorLoadAction: didEncode ? .load : colorLoadAction,
                        depthLoadAction: didEncode ? .load : depthLoadAction,
                        stencilLoadAction: didEncode ? .load : stencilLoadAction,
                        colorStoreAction: hasClassicTransparentRenderables ? .store : finalColorStoreAction,
                        depthStoreAction: hasClassicTransparentRenderables ? .store : finalDepthStoreAction,
                        stencilStoreAction: hasClassicTransparentRenderables ? .store : finalStencilStoreAction
                    )
                    let alphaEncoded = prepareAlphaOitRoute(
                        renderPassDescriptor: renderPassDescriptor,

                        viewports: viewports,
                        simdViewports: simdViewports,
                        viewMappings: viewMappings,
                        clearWhenEmpty: !didEncode,
                        colorLoadAction: didEncode ? .load : colorLoadAction,
                        depthLoadAction: didEncode ? .load : depthLoadAction,
                        stencilLoadAction: didEncode ? .load : stencilLoadAction,
                        colorStoreAction: hasClassicTransparentRenderables ? .store : finalColorStoreAction,
                        depthStoreAction: hasClassicTransparentRenderables ? .store : finalDepthStoreAction,
                        stencilStoreAction: hasClassicTransparentRenderables ? .store : finalStencilStoreAction
                    )
                    didEncode = didEncode || alphaEncoded
                }

                if hasClassicTransparentRenderables {
                    configureMainAttachments(
                        renderPassDescriptor: renderPassDescriptor,
                        colorLoadAction: didEncode ? .load : colorLoadAction,
                        depthLoadAction: didEncode ? .load : depthLoadAction,
                        stencilLoadAction: didEncode ? .load : stencilLoadAction,
                        colorStoreAction: finalColorStoreAction,
                        depthStoreAction: finalDepthStoreAction,
                        stencilStoreAction: finalStencilStoreAction
                    )
                    configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
                    let transparentEncoded = prepareRoute(
                        renderPassDescriptor: renderPassDescriptor,

                        route: .classicTransparent,
                        phase: .classicTransparent,
                        label: "Classic Transparent Forward",

                        viewports: viewports,
                        simdViewports: simdViewports,
                        viewMappings: viewMappings,
                        auxiliaryAttachmentIndices: [],
                        clearWhenEmpty: !didEncode
                    )
                    didEncode = didEncode || transparentEncoded
                }
            }

            return didEncode
        }
    }

    // MARK: - Internal Update

    private func update(scene: Object, cameras: [Camera], viewports: [simd_float4], recorder: PacketRecorder, encodingContext: EncodingContext?,
                         lightOccurrences: [RecordedLightOccurrence] = []) {
        for camera in cameras {
            camera.update()
        }

        onUpdate?()

        renderCollection.reset()
        sceneTraversal.updateAndCollect(scene: scene, into: renderCollection)
        renderCollection.includeLights(lightOccurrences)

        updateScene(
            cameras: cameras,
            viewports: viewports,
            recorder: recorder, encodingContext: encodingContext
        )

        updateLights(recordedLights: lightOccurrences)
        recorder.passBindings.lights = recorder.snapshot(uploadedLightData)
        recorder.passBindings.bindsLights = !renderCollection.lightReceivers.isEmpty
    }

    private func updateScene(cameras: [Camera], viewports: [simd_float4], recorder: PacketRecorder, encodingContext: EncodingContext?,
                             runsMaterialUpdates: Bool = true) {
        updateDirectLightingState(recorder: recorder)

        let lightCount = renderCollection.lights.count
        let directShadowCount = directShadowLights.count
        let directShadowTextureCount = directShadowTextures.count
        let projectorCount = projectorLights.count

        var cubemapTexture: MTLTexture?
        activeEnvironmentIntensity = 1.0
        activeReflectionTexture = nil
        activeIrradianceTexture = nil
        activeBrdfTexture = nil
        activeReflectionTexcoordTransform = matrix_identity_float3x3
        activeIrradianceTexcoordTransform = matrix_identity_float3x3

        for collectedObject in renderCollection.objects {
            let object = collectedObject.object

            if let environment = collectedObject.environment {
                activeEnvironmentIntensity = environment.environmentIntensity
                cubemapTexture = environment.cubemapTexture

                activeReflectionTexture = environment.reflectionTexture
                activeReflectionTexcoordTransform = environment.reflectionTexcoordTransform

                activeIrradianceTexture = environment.irradianceTexture
                activeIrradianceTexcoordTransform = environment.irradianceTexcoordTransform

                activeBrdfTexture = environment.brdfTexture
            }

            if let renderable = collectedObject.renderable {
                for material in renderable.materials {
                    let usesDeferredResolve = renderingMode == .deferredGeometry
                        && material.lightingModel == .surface
                        && material.blending == .disabled

                    if material.lighting {
                        material.lightCount = usesDeferredResolve ? 0 : lightCount
                        material.projectorCount = usesDeferredResolve ? 0 : projectorCount
                    } else {
                        material.lightCount = 0
                        material.projectorCount = 0
                    }

                    // A scene setting for every lit material: whether a mesh actually samples the
                    // shadow maps is its own receiveShadow, stated per draw (see DrawLayout).
                    if material.lighting, !usesDeferredResolve {
                        material.directShadowCount = directShadowCount
                        material.directShadowTextureCount = directShadowTextureCount
                    } else {
                        material.directShadowCount = 0
                        material.directShadowTextureCount = 0
                    }

                    if let pbrMaterial = material as? StandardMaterial {
                        pbrMaterial.environmentIntensity = activeEnvironmentIntensity
                        if let reflectionTexture = activeReflectionTexture {
                            pbrMaterial.setTexture(reflectionTexture, type: .reflection)
                            pbrMaterial.setTexcoordTransform(activeReflectionTexcoordTransform, type: .reflection)
                        }
                        if let irradianceTexture = activeIrradianceTexture {
                            pbrMaterial.setTexture(irradianceTexture, type: .irradiance)
                            pbrMaterial.setTexcoordTransform(activeIrradianceTexcoordTransform, type: .irradiance)
                        }
                        if let brdfTexture = activeBrdfTexture {
                            pbrMaterial.setTexture(brdfTexture, type: .brdf)
                        }
                    }

                    if let cubemapTexture = cubemapTexture, let skyboxMaterial = material as? SkyboxMaterial {
                        skyboxMaterial.texture = cubemapTexture
                        skyboxMaterial.texcoordTransform = simd_float4x4(textureTransform: activeReflectionTexcoordTransform)
                        skyboxMaterial.environmentIntensity = activeEnvironmentIntensity
                    }

                    if runsMaterialUpdates {
                        material.update()
                    } else {
                        // Recording captures the state the caller updated. Refresh bindings and
                        // pipelines for scene settings without running procedural update hooks again.
                        material.updateDepth()
                        material.updateShader()
                    }
                }
            }

            if let encodingContext { object.encode(in: encodingContext) }
        }
    }

    // MARK: - Pass planning (producer only)

    private func appendPreparedPass(_ descriptor: MTLRenderPassDescriptor, label: String, viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping]) -> Int {
        let index = preparedPasses.count
        preparedPasses.append(RecordedRenderPass(descriptor: descriptor, label: label, viewports: viewports,
                                                amplificationCount: context.vertexAmplificationCount, viewMappings: viewMappings,
                                                bindings: recorder?.passBindings ?? RenderPassBindings()))
        return index
    }

    private func prepareEntries(_ descriptor: MTLRenderPassDescriptor, entries: [RenderRouteEntry], label: String,
                                viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping],
                                auxiliaryAttachmentIndices: [Int], clearWhenEmpty: Bool) -> Bool {
        if entries.isEmpty {
            guard clearWhenEmpty else { return false }
            _ = appendPreparedPass(descriptor, label: label + " Empty Pass", viewports: viewports, viewMappings: viewMappings)
            return true
        }
        let colorStore = descriptor.colorAttachments[0].storeAction
        let depthStore = descriptor.depthAttachment.storeAction
        let stencilStore = descriptor.stencilAttachment.storeAction
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                descriptor.colorAttachments[0].loadAction = .load
                descriptor.depthAttachment.loadAction = .load
                descriptor.stencilAttachment.loadAction = .load
                for attachment in auxiliaryAttachmentIndices { colorAttachment(descriptor, index: attachment)?.loadAction = .load }
            }
            let final = index == entries.count - 1
            descriptor.colorAttachments[0].storeAction = final ? colorStore : .store
            descriptor.depthAttachment.storeAction = final ? depthStore : .store
            descriptor.stencilAttachment.storeAction = final ? stencilStore : .store
            let pass = appendPreparedPass(descriptor, label: "\(self.label) \(label) Pass \(entry.pass)", viewports: viewports, viewMappings: viewMappings)
            preparedPasses[pass].commands.append(.indices(entry.packets, viewIndex: 0))
        }
        return true
    }

    // MARK: - Resizing

    public func resize(_ size: (width: Float, height: Float)) {
        self.size = size
    }

    private func updateViewport() {
        viewport = MTLViewport(
            originX: 0.0,
            originY: 0.0,
            width: Double(size.width),
            height: Double(size.height),
            znear: invertViewportNearFar ? 1.0 : 0.0,
            zfar: invertViewportNearFar ? 0.0 : 1.0
        )
    }

    // MARK: - Color Textures

    private func setupColorTexture(arrayLength: Int) {
        guard updateColorTexture, colorPixelFormat != .invalid, size.width > 1, size.height > 1 else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: colorPixelFormat,
                width: Int(size.width),
                height: Int(size.height),
                mipmapped: false
            )
        descriptor.sampleCount = 1
        descriptor.textureType = arrayLength > 1 ? .type2DArray : .type2D
        descriptor.arrayLength = arrayLength
        descriptor.usage = frameBufferOnly ? .renderTarget : [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = colorTextureStorageMode
        descriptor.resourceOptions = .storageModePrivate

        colorTexture = context.device.makeTexture(descriptor: descriptor)
        colorTexture?.label = label + " Color Texture"

        updateColorTexture = false
    }

    private func setupColorMultisampleTexture(arrayLength: Int) {
        guard updateColorMultisampleTexture,
              colorPixelFormat != .invalid,
              context.sampleCount > 1,
              size.width > 0,
              size.height > 0
        else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: colorPixelFormat,
                width: Int(size.width),
                height: Int(size.height),
                mipmapped: false
            )
        descriptor.sampleCount = context.sampleCount
        descriptor.textureType = arrayLength > 1 ? .type2DMultisampleArray : .type2DMultisample
        descriptor.arrayLength = arrayLength
        descriptor.usage = .renderTarget
        descriptor.storageMode = colorMultisampleTextureStorageMode
        descriptor.resourceOptions = .storageModePrivate

        colorMultisampleTexture = context.device.makeTexture(descriptor: descriptor)
        colorMultisampleTexture?.label = label + "Multisample Color Texture"

        updateColorMultisampleTexture = false
    }

    // MARK: - Depth Textures

    private func setupDepthTexture(arrayLength: Int) {
        guard updateDepthTexture,
              depthPixelFormat != .invalid,
              size.width > 0,
              size.height > 0
        else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: depthPixelFormat,
                width: Int(size.width),
                height: Int(size.height),
                mipmapped: false
            )
        descriptor.sampleCount = 1
        descriptor.textureType = arrayLength > 1 ? .type2DArray : .type2D
        descriptor.arrayLength = arrayLength
        descriptor.usage = frameBufferOnly ? .renderTarget : [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = depthTextureStorageMode
        descriptor.resourceOptions = .storageModePrivate

        depthTexture = context.device.makeTexture(descriptor: descriptor)
        depthTexture?.label = label + " Depth Texture"

        updateDepthTexture = false
    }

    private func setupDepthMultisampleTexture(arrayLength: Int) {
        guard updateDepthMultisampleTexture,
              depthPixelFormat != .invalid,
              context.sampleCount > 1,
              size.width > 0,
              size.height > 0
        else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: depthPixelFormat,
                width: Int(size.width),
                height: Int(size.height),
                mipmapped: false
            )
        descriptor.sampleCount = context.sampleCount
        descriptor.textureType = arrayLength > 1 ? .type2DMultisampleArray : .type2DMultisample
        descriptor.arrayLength = arrayLength
        descriptor.usage = .renderTarget
        descriptor.storageMode = depthMultisampleTextureStorageMode
        descriptor.resourceOptions = .storageModePrivate

        depthMultisampleTexture = context.device.makeTexture(descriptor: descriptor)
        depthMultisampleTexture?.label = label + "Multisample Depth Texture"

        updateDepthMultisampleTexture = false
    }

    // MARK: - Stencil Textures

    private func setupStencilTexture(arrayLength: Int) {
        guard updateStencilTexture,
              stencilPixelFormat != .invalid,
              size.width > 1,
              size.height > 1
        else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = stencilPixelFormat
        descriptor.width = Int(size.width)
        descriptor.height = Int(size.height)
        descriptor.sampleCount = 1
        descriptor.textureType = arrayLength > 1 ? .type2DArray : .type2D
        descriptor.arrayLength = arrayLength
        descriptor.usage = frameBufferOnly ? .renderTarget : [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .memoryless
        descriptor.resourceOptions = .storageModePrivate

        stencilTexture = context.device.makeTexture(descriptor: descriptor)
        stencilTexture?.label = label + " Stencil Texture"

        updateStencilTexture = false
    }

    private func setupStencilMultisampleTexture(arrayLength: Int) {
        guard updateStencilMultisampleTexture,
              stencilPixelFormat != .invalid,
              context.sampleCount > 1,
              size.width > 0,
              size.height > 0 else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = stencilPixelFormat
        descriptor.width = Int(size.width)
        descriptor.height = Int(size.height)
        descriptor.sampleCount = context.sampleCount
        descriptor.textureType = arrayLength > 1 ? .type2DMultisampleArray : .type2DMultisample
        descriptor.arrayLength = arrayLength
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .memoryless
        descriptor.resourceOptions = .storageModePrivate

        stencilMultisampleTexture = context.device.makeTexture(descriptor: descriptor)
        stencilMultisampleTexture?.label = label + "Multisample Stencil Texture"

        updateStencilTexture = false
    }

    // MARK: - Lights

    /// Rebuilds the collected lights' data when any light, its order, its transform, its properties
    /// or its assigned shadow or projector index changed. Runs after `updateDirectLightingState`,
    /// which re-aims the lights' views and assigns those indices.
    private func updateLights(recordedLights: [RecordedLightOccurrence]) {
        let lights = renderCollection.lights
        guard !lights.isEmpty else {
            uploadedLights.removeAll(keepingCapacity: true)
            uploadedLightData.removeAll(keepingCapacity: true)
            return
        }

        // includeLights appends the captured occurrences after the live scene lights.
        // Read their existing record identities directly: no casts, hashes or new IDs.
        let liveLightCount = lights.count - recordedLights.count
        func identity(at index: Int) -> UploadedLight.Identity {
            if index >= liveLightCount {
                return .recorded(recordedLights[index - liveLightCount].identity)
            }
            return .object(ObjectIdentifier(lights[index]))
        }

        var changed = lights.count != uploadedLights.count
        if !changed {
            for (index, light) in lights.enumerated() {
                let uploaded = uploadedLights[index]
                if uploaded.identity != identity(at: index) || uploaded.worldRevision != light.worldRevision
                    || uploaded.lightRevision != light.lightRevision || uploaded.shadowIndex != light.shadowIndex
                    || uploaded.projectorIndex != light.projectorIndex
                {
                    changed = true
                    break
                }
            }
        }
        guard changed else { return }

        uploadedLights.removeAll(keepingCapacity: true)
        uploadedLightData.removeAll(keepingCapacity: true)
        for (index, light) in lights.enumerated() {
            uploadedLights.append(UploadedLight(
                identity: identity(at: index),
                worldRevision: light.worldRevision,
                lightRevision: light.lightRevision,
                shadowIndex: light.shadowIndex,
                projectorIndex: light.projectorIndex
            ))
            uploadedLightData.append(light.data)
        }
        lightDataUploadCount += 1
    }

    private func updateDirectLightingState(recorder: PacketRecorder) {
        directShadowLights.removeAll(keepingCapacity: true)
        directShadowTextures.removeAll(keepingCapacity: true)
        projectorLights.removeAll(keepingCapacity: true)
        projectorTextures.removeAll(keepingCapacity: true)

        var directShadowData = [ShadowData]()
        var directShadowMatrices = [simd_float4x4]()
        var projectorMatrices = [simd_float4x4]()
        var projectorTransforms = [simd_float4x4]()

        var directShadowIndex = 0
        var directShadowTextureIndex = 0
        var directShadowMatrixIndex = 0
        var projectorIndex = 0

        for light in renderCollection.lights {
            // In order: lights re-aim their shadow and projector views if they moved or changed
            // (by revision), then get their shadow and projector indices, then `updateLights`
            // uploads their data.
            light.updateViewIfNeeded()
            light.shadowIndex = -1
            light.projectorIndex = -1

            if let captured = light as? RecordedLightOccurrence,
               let texture = captured.projectorTexture, let matrix = captured.projectorMatrix,
               let transform = captured.projectorTransform, projectorIndex < maxProjectors {
                light.projectorIndex = projectorIndex
                projectorLights.append(light)
                projectorTextures.append(texture)
                projectorMatrices.append(matrix)
                projectorTransforms.append(transform)
                projectorIndex += 1
            } else if let spotLight = light as? SpotLight,
               let projectionTexture = spotLight.projectionTexture,
               projectorIndex < maxProjectors
            {
                light.projectorIndex = projectorIndex
                projectorLights.append(spotLight)
                projectorTextures.append(projectionTexture)
                projectorMatrices.append(spotLight.projectorMatrix)
                projectorTransforms.append(simd_float4x4(textureTransform: spotLight.projectionTransform))
                projectorIndex += 1
            }

            guard light.castShadow,
                  light.shadow.enabled,
                  directShadowIndex < maxShadowedLights
            else { continue }

            let shadow = light.shadow
            let shadowTextures = shadow.textures
            let shadowMatrices = shadow.matrices
            guard !shadowTextures.isEmpty,
                  !shadowMatrices.isEmpty,
                  directShadowTextureIndex + shadowTextures.count <= maxShadowTextures,
                  directShadowMatrixIndex + shadowMatrices.count <= maxShadowTextures
            else { continue }

            light.shadowIndex = directShadowIndex
            directShadowLights.append(light)
            directShadowData.append(
                ShadowData(
                    strength: shadow.strength,
                    bias: shadow.bias,
                    normalBias: shadow.normalBias,
                    radius: shadow.radius,
                    textureIndex: UInt32(directShadowTextureIndex),
                    matrixIndex: UInt32(directShadowMatrixIndex),
                    viewCount: UInt32(shadow.viewCount)
                )
            )
            directShadowMatrices.append(contentsOf: shadowMatrices)

            directShadowIndex += 1
            directShadowTextureIndex += shadowTextures.count
            directShadowMatrixIndex += shadowMatrices.count
        }

        directShadowTextures = Array(repeating: nil, count: directShadowTextureIndex)
        projectorTextures = Array(repeating: nil, count: projectorLights.count)

        recorder.passBindings.shadowData = recorder.snapshot(directShadowData)
        recorder.passBindings.shadowMatrices = recorder.snapshot(directShadowMatrices)
        recorder.passBindings.projectorMatrices = recorder.snapshot(projectorMatrices)
        recorder.passBindings.projectorTransforms = recorder.snapshot(projectorTransforms)
    }

    private func updateDirectShadowTextures() {
        directShadowTextures = directShadowLights.flatMap { light in
            light.shadow.textures.map(Optional.some)
        }
    }

    private func updateProjectorTextures() {
        projectorTextures = projectorLights.map { light in
            if let captured = light as? RecordedLightOccurrence { return captured.projectorTexture }
            return (light as? SpotLight)?.projectionTexture
        }
    }

    // MARK: - Output Textures

    private func setupAlbedoTexture() {
        guard updateAlbedoTexture, size.width > 1, size.height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.albedoPixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = albedoTextureStorageMode
        albedoTexture = context.device.makeTexture(descriptor: descriptor)
        albedoTexture?.label = label + " Albedo Texture"
        updateAlbedoTexture = false
    }

    private func setupNormalTexture() {
        guard updateNormalTexture, size.width > 1, size.height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.normalsPixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = normalTextureStorageMode
        normalTexture = context.device.makeTexture(descriptor: descriptor)
        normalTexture?.label = label + " Normal Texture"
        updateNormalTexture = false
    }

    private func setupPBRTexture() {
        guard updatePBRTexture, size.width > 1, size.height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pbrPixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = pbrTextureStorageMode
        pbrTexture = context.device.makeTexture(descriptor: descriptor)
        pbrTexture?.label = label + " PBR Texture"
        updatePBRTexture = false
    }

    private func setupVelocityTexture() {
        guard updateVelocityTexture, size.width > 1, size.height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.velocityPixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = velocityTextureStorageMode
        velocityTexture = context.device.makeTexture(descriptor: descriptor)
        velocityTexture?.label = label + " Velocity Texture"
        updateVelocityTexture = false
    }

    private func setupEmissiveTexture() {
        guard updateEmissiveTexture, size.width > 1, size.height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.emissivePixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = emissiveTextureStorageMode
        emissiveTexture = context.device.makeTexture(descriptor: descriptor)
        emissiveTexture?.label = label + " Emissive Texture"
        updateEmissiveTexture = false
    }

}

private final class AlphaOitResources {
    private unowned let renderer: RenderEncoder
    private var cachedResources: Resources?

    struct Resources {
        let tilePipeline: MTLRenderPipelineState
        let blendPipeline: MTLRenderPipelineState
        let blendDepthStencilState: MTLDepthStencilState
    }

    init(renderer: RenderEncoder) {
        self.renderer = renderer
    }

    func load() throws -> Resources {
        if let cachedResources {
            return cachedResources
        }

        guard let pipelineURL = getPipelinesCommonURL("AlphaOIT.metal") else {
            throw NSError(domain: "Satin.RenderEncoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing AlphaOIT pipeline source"])
        }
        let source = try String(contentsOf: pipelineURL)
        let library = try renderer.context.device.makeLibrary(source: source, options: nil)

        guard let tileFunction = library.makeFunction(name: "alphaOitClearTileData"),
              let blendVertex = library.makeFunction(name: "alphaOitBlendVertex"),
              let blendFragment = library.makeFunction(name: "alphaOitBlendFragment")
        else {
            throw NSError(domain: "Satin.RenderEncoder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing AlphaOIT shader functions"])
        }

        let tileDescriptor = MTLTileRenderPipelineDescriptor()
        tileDescriptor.label = "\(renderer.label) Alpha OIT Tile Init"
        tileDescriptor.tileFunction = tileFunction
        tileDescriptor.colorAttachments[0].pixelFormat = renderer.colorPixelFormat
        tileDescriptor.threadgroupSizeMatchesTileSize = true
        let tilePipeline = try renderer.context.device.makeRenderPipelineState(
            tileDescriptor: tileDescriptor,
            options: [],
            reflection: nil
        )

        let blendDescriptor = MTLRenderPipelineDescriptor()
        blendDescriptor.label = "\(renderer.label) Alpha OIT Blend"
        blendDescriptor.vertexFunction = blendVertex
        blendDescriptor.fragmentFunction = blendFragment
        blendDescriptor.colorAttachments[0].pixelFormat = renderer.colorPixelFormat
        blendDescriptor.depthAttachmentPixelFormat = renderer.depthPixelFormat
        blendDescriptor.stencilAttachmentPixelFormat = renderer.stencilPixelFormat
        let blendPipeline = try renderer.context.device.makeRenderPipelineState(descriptor: blendDescriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.label = "\(renderer.label) Alpha OIT Blend Depth"
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let blendDepthStencilState = renderer.context.device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw NSError(domain: "Satin.RenderEncoder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create AlphaOIT depth state"])
        }

        let resources = Resources(
            tilePipeline: tilePipeline,
            blendPipeline: blendPipeline,
            blendDepthStencilState: blendDepthStencilState
        )
        cachedResources = resources
        return resources
    }
}
