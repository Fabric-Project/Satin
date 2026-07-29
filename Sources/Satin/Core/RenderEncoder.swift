//
//  RenderEncoder.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Metal
import simd

open class RenderEncoder {
    public var label = "Satin RenderEncoder"

    public var onUpdate: (() -> Void)?

    public var sortObjects: Bool

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

    public var clearColor: MTLClearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)

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

    public var colorLoadAction: MTLLoadAction
    public var colorStoreAction: MTLStoreAction

    // MARK: - Depth Textures

    public var clearDepth: Double

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

    public var depthLoadAction: MTLLoadAction
    public var depthStoreAction: MTLStoreAction

    // MARK: - Stencil Textures

    public var clearStencil: UInt32

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

    public var stencilLoadAction: MTLLoadAction
    public var stencilStoreAction: MTLStoreAction

    // MARK: - RenderEncoder Outputs

    /// Controls whether the renderer runs a traditional forward pass, a forward MRT pass,
    /// or the deferred geometry stage. Switching modes compiles new pipeline variants on
    /// the next frame, so avoid changing this every frame.
    public var renderingMode: RenderingMode

    /// Declares which auxiliary outputs the renderer should produce in addition to color.
    /// Each active flag adds a texture allocation and an extra color attachment write.
    /// The current MRT path requires `context.sampleCount == 1` whenever auxiliary outputs
    /// are enabled.
    public var activeOutputs: RendererOutputs

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

    private struct RenderContextKey: Hashable {
        let renderingMode: RenderingMode
        let activeOutputs: RendererOutputs
        let alphaOitEnabled: Bool
        let colorPixelFormat: MTLPixelFormat
        let depthPixelFormat: MTLPixelFormat
        let stencilPixelFormat: MTLPixelFormat
    }

    // The encoding phase applied when drawing a collected set of renderables.
    // Controls which render Context is built (shader defines, G-buffer outputs, OIT flag)
    // and sets renderable.materialPass so Mesh.materialMatchesCurrentPass can gate
    // per-material drawing within a single encoder.
    private enum MaterialPassType {
        // All opaque geometry in a plain forward pass. No G-buffer outputs, no OIT.
        // Used for every opaque renderable in .forward rendering mode (surface-lit and
        // unlit alike). Sets materialPass = .opaque so all non-transparent materials draw.
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
    private enum RenderRoute {
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

    private struct CurrentEncodePass {
        let cameras: [Camera]
        let viewports: [simd_float4]
        let phase: MaterialPassType
        let overrideMaterial: Material?
    }

    private struct ScheduledCurrentPassEncodingCommand {
        let renderLayer: Int
        let routeRenderables: [Renderable]
        let encode: (RenderEncoderState) -> Void
    }

    private struct RenderRouteEntry {
        let pass: Int
        let renderables: [Renderable]
        let commands: [ScheduledCurrentPassEncodingCommand]
    }

    private struct ColorAttachmentState {
        let texture: MTLTexture?
        let resolveTexture: MTLTexture?
        let loadAction: MTLLoadAction
        let storeAction: MTLStoreAction
        let clearColor: MTLClearColor
    }

    private var renderContextCache: [RenderContextKey: Context] = [:]
    private var currentEncodePass: CurrentEncodePass?
    private var scheduledCurrentPassEncodingCommands = [ScheduledCurrentPassEncodingCommand]()
    private let supportsAlphaOit: Bool
    private let alphaOitTileSize = MTLSize(width: 32, height: 16, depth: 1)
    private lazy var alphaOitResources = AlphaOitResources(renderer: self)

    private func colorAttachment(_ renderPassDescriptor: MTLRenderPassDescriptor, index: Int) -> MTLRenderPassColorAttachmentDescriptor? {
        renderPassDescriptor.colorAttachments[index]
    }

    private var objectList = [Object]()
    private var renderLists = [Int: RenderList]()

    private var lightList = [Light]()
    private var lightReceivers = [Renderable]()
    private var _updateLightDataBuffer = false
    private var lightDataBuffer: StructBuffer<LightData>?
    private var lightDataSubscriptions = Set<AnyCancellable>()

    private var shadowCasters = [Renderable]()
    private var shadowReceivers = [Renderable]()

    private var directShadowLights = [Light]()
    private var directShadowTextures = [MTLTexture?]()
    private var directShadowDataBuffer: StructBuffer<ShadowData>?
    private var directShadowMatricesBuffer: StructBuffer<simd_float4x4>?

    private var projectorLights = [SpotLight]()
    private var projectorTextures = [MTLTexture?]()
    private var projectorMatricesBuffer: StructBuffer<simd_float4x4>?
    private var projectorTransformsBuffer: StructBuffer<simd_float4x4>?

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
        self.sortObjects = sortObjects
        self.renderingMode = context.renderingMode
        self.activeOutputs = RendererOutputs(rawValue: context.activeOutputs.rawValue | RendererOutputs.color.rawValue)

        self.clearColor = MTLClearColor(clearColor)
        self.colorLoadAction = colorLoadAction
        self.colorStoreAction = colorStoreAction

        self.clearDepth = clearDepth
        self.depthLoadAction = depthLoadAction
        self.depthStoreAction = depthStoreAction

        self.clearStencil = clearStencil
        self.stencilLoadAction = stencilLoadAction
        self.stencilStoreAction = stencilStoreAction

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
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        scene: Object,
        camera: Camera,
        viewport: MTLViewport? = nil,
        renderTarget: MTLTexture
    ) {
        if context.sampleCount > 1 {
            let resolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
            renderPassDescriptor.colorAttachments[0].resolveTexture = renderTarget
            draw(
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: [camera],
                viewports: [viewport ?? self.viewport]
            )
            renderPassDescriptor.colorAttachments[0].resolveTexture = resolveTexture
        } else {
            let renderTexture = renderPassDescriptor.colorAttachments[0].texture
            renderPassDescriptor.colorAttachments[0].texture = renderTarget
            draw(
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: [camera],
                viewports: [viewport ?? self.viewport]
            )
            renderPassDescriptor.colorAttachments[0].texture = renderTexture
        }
    }

    public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, cameras: [Camera], viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = [], renderTarget: MTLTexture) {
        if context.sampleCount > 1 {
            let resolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
            renderPassDescriptor.colorAttachments[0].resolveTexture = renderTarget
            draw(
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: cameras,
                viewports: viewports,
                viewMappings: viewMappings
            )
            renderPassDescriptor.colorAttachments[0].resolveTexture = resolveTexture
        } else {
            let renderTexture = renderPassDescriptor.colorAttachments[0].texture
            renderPassDescriptor.colorAttachments[0].texture = renderTarget
            draw(
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                scene: scene,
                cameras: cameras,
                viewports: viewports,
                viewMappings: viewMappings
            )
            renderPassDescriptor.colorAttachments[0].texture = renderTexture
        }
    }

    // https://developer.apple.com/documentation/metal/render_passes/improving_rendering_performance_with_vertex_amplification?language=objc
    // https://developer.apple.com/documentation/metal/render_passes/rendering_to_multiple_viewports_in_a_draw_command?language=objc

    public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, camera: Camera, viewport: MTLViewport? = nil) {
        draw(
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
    public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, cameras: [Camera], viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = []) {
        defer {
            scheduledCurrentPassEncodingCommands.removeAll(keepingCapacity: true)
        }

        let simd_viewports = viewports.map(\.float4)
        update(
            commandBuffer: commandBuffer,
            scene: scene,
            cameras: cameras,
            viewports: simd_viewports
        )

        var arrayLength = 1
        for viewMapping in viewMappings {
            arrayLength = max(arrayLength, Int(viewMapping.renderTargetArrayIndexOffset) + 1)
        }

        // render objects that cast shadows into the depth textures
        if !shadowCasters.isEmpty, !shadowReceivers.isEmpty {
            for light in lightList where light.castShadow {
                if light.shadow.shouldRender {
                    light.shadow.draw(context: context, commandBuffer: commandBuffer, renderables: shadowCasters)
                }
            }
        }

        let inColorStoreAction = renderPassDescriptor.colorAttachments[0].storeAction
        let inColorLoadAction = renderPassDescriptor.colorAttachments[0].loadAction
        let inColorTexture = renderPassDescriptor.colorAttachments[0].texture
        let inColorResolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture

        let inDepthStoreAction = renderPassDescriptor.depthAttachment.storeAction
        let inDepthLoadAction = renderPassDescriptor.depthAttachment.loadAction
        let inDepthTexture = renderPassDescriptor.depthAttachment.texture
        let inDepthResolveTexture = renderPassDescriptor.depthAttachment.resolveTexture

        let inStencilStoreAction = renderPassDescriptor.stencilAttachment.storeAction
        let inStencilLoadAction = renderPassDescriptor.stencilAttachment.loadAction
        let inStencilTexture = renderPassDescriptor.stencilAttachment.texture
        let inStencilResolveTexture = renderPassDescriptor.stencilAttachment.resolveTexture
        let inTileWidth = renderPassDescriptor.tileWidth
        let inTileHeight = renderPassDescriptor.tileHeight
        let inImageblockSampleLength = renderPassDescriptor.imageblockSampleLength
        let inAuxiliaryStates: [Int: ColorAttachmentState] = Dictionary(
            uniqueKeysWithValues: (1...5).compactMap { index in
                guard let attachment = colorAttachment(renderPassDescriptor, index: index) else { return nil }
                return (index, ColorAttachmentState(
                    texture: attachment.texture,
                    resolveTexture: attachment.resolveTexture,
                    loadAction: attachment.loadAction,
                    storeAction: attachment.storeAction,
                    clearColor: attachment.clearColor
                ))
            }
        )

        defer {
            renderPassDescriptor.colorAttachments[0].storeAction = inColorStoreAction
            renderPassDescriptor.colorAttachments[0].loadAction = inColorLoadAction
            renderPassDescriptor.colorAttachments[0].texture = inColorTexture
            renderPassDescriptor.colorAttachments[0].resolveTexture = inColorResolveTexture

            renderPassDescriptor.depthAttachment.storeAction = inDepthStoreAction
            renderPassDescriptor.depthAttachment.loadAction = inDepthLoadAction
            renderPassDescriptor.depthAttachment.texture = inDepthTexture
            renderPassDescriptor.depthAttachment.resolveTexture = inDepthResolveTexture

            renderPassDescriptor.stencilAttachment.storeAction = inStencilStoreAction
            renderPassDescriptor.stencilAttachment.loadAction = inStencilLoadAction
            renderPassDescriptor.stencilAttachment.texture = inStencilTexture
            renderPassDescriptor.stencilAttachment.resolveTexture = inStencilResolveTexture
            renderPassDescriptor.tileWidth = inTileWidth
            renderPassDescriptor.tileHeight = inTileHeight
            renderPassDescriptor.imageblockSampleLength = inImageblockSampleLength

            for (index, state) in inAuxiliaryStates {
                guard let attachment = colorAttachment(renderPassDescriptor, index: index) else { continue }
                attachment.texture = state.texture
                attachment.resolveTexture = state.resolveTexture
                attachment.loadAction = state.loadAction
                attachment.storeAction = state.storeAction
                attachment.clearColor = state.clearColor
            }
        }

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

        _ = encodeMainRenderPasses(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            cameras: cameras,
            viewports: viewports,
            simdViewports: simd_viewports,
            viewMappings: viewMappings,
            finalColorStoreAction: finalColorStoreAction,
            finalDepthStoreAction: finalDepthStoreAction,
            finalStencilStoreAction: finalStencilStoreAction
        )
    }

    public func scheduleCurrentPassEncoding(
        scene: Object,
        encode: @escaping (RenderEncoderState) -> Void
    ) {
        var renderables = [Renderable]()
        collectCurrentPassRenderables(
            object: scene,
            parentVisible: true,
            renderables: &renderables
        )
        scheduleCurrentPassEncoding(
            renderables: renderables,
            encode: encode
        )
    }

    public func scheduleCurrentPassEncoding(
        renderables: [Renderable],
        encode: @escaping (RenderEncoderState) -> Void
    ) {
        let visibleRenderables = renderables.filter(\.isVisible)
        guard !visibleRenderables.isEmpty else { return }

        let renderablesByLayer = Dictionary(grouping: visibleRenderables) {
            $0.renderLayer.rawValue
        }

        for (renderLayer, layerRenderables) in renderablesByLayer {
            scheduledCurrentPassEncodingCommands.append(
                ScheduledCurrentPassEncodingCommand(
                    renderLayer: renderLayer,
                    routeRenderables: layerRenderables,
                    encode: encode
                )
            )
        }
    }

    public func encodeCurrentPass(
        scene: Object,
        renderEncoderState: RenderEncoderState,
        repeatedIteration: Int? = nil,
        repeatedCount: Int = 1
    ) {
        var renderables = [Renderable]()
        collectCurrentPassRenderables(
            object: scene,
            parentVisible: true,
            renderables: &renderables
        )
        encodeCurrentPass(
            renderables: renderables,
            renderEncoderState: renderEncoderState,
            repeatedIteration: repeatedIteration,
            repeatedCount: repeatedCount
        )
    }

    public func encodeCurrentPass(
        renderables: [Renderable],
        renderEncoderState: RenderEncoderState,
        repeatedIteration: Int? = nil,
        repeatedCount: Int = 1
    ) {
        guard let currentEncodePass else {
            assertionFailure("encodeCurrentPass called outside an active Satin encode pass.")
            return
        }

        let visibleRenderables = renderables.filter(\.isVisible)
        let orderedRenderables = sortObjects
            ? visibleRenderables.sorted { $0.renderOrder < $1.renderOrder }
            : visibleRenderables

        for renderable in orderedRenderables {
            encodeCurrentPassRenderable(
                renderable,
                currentEncodePass: currentEncodePass,
                renderEncoderState: renderEncoderState,
                repeatedIteration: repeatedIteration,
                repeatedCount: repeatedCount
            )
        }
    }

    private func collectCurrentPassRenderables(
        object: Object,
        parentVisible: Bool,
        renderables: inout [Renderable]
    ) {
        let visible = parentVisible && object.visible
        guard visible else { return }

        if let renderable = object as? Renderable {
            renderables.append(renderable)
        }

        for child in object.children {
            collectCurrentPassRenderables(
                object: child,
                parentVisible: visible,
                renderables: &renderables
            )
        }
    }

    private func encodeCurrentPassRenderable(
        _ renderable: Renderable,
        currentEncodePass: CurrentEncodePass,
        renderEncoderState: RenderEncoderState,
        repeatedIteration: Int?,
        repeatedCount: Int
    ) {
        let repeatedCount = max(1, repeatedCount)
        let drawContext = currentEncodePass.overrideMaterial?.context ?? renderContext(
            for: renderable,
            phase: currentEncodePass.phase
        )

        if let repeatedIteration {
            renderable.ensureVertexUniformBuffer(
                context: drawContext,
                encodesPerFrame: max(Satin.maxSubPassesPerFrame, repeatedCount)
            )

            renderable.selectRepeatedEncodingState(
                iteration: repeatedIteration,
                count: repeatedCount
            )
        } else if renderable.vertexUniforms[drawContext.id] == nil {
            renderable.ensureVertexUniformBuffer(context: drawContext)
        }

        guard renderable.isDrawable(renderContext: drawContext, shadow: false) else { return }

        _encode(
            renderEncoder: renderEncoderState.renderEncoder,
            renderEncoderState: renderEncoderState,
            renderable: renderable,
            cameras: currentEncodePass.cameras,
            viewports: currentEncodePass.viewports,
            phase: currentEncodePass.phase,
            overrideMaterial: currentEncodePass.overrideMaterial
        )
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

    private func usesAlphaOit(_ material: Material) -> Bool {
        supportsAlphaOit &&
            material.blending == .alpha &&
            material.supportsAlphaOrderIndependentTransparency
    }

    private func materials(for renderable: Renderable) -> [Material] {
        if !renderable.materials.isEmpty {
            return renderable.materials
        }
        return [renderable.material].compactMap { $0 }
    }

    private func shouldRender(_ renderable: Renderable, route: RenderRoute) -> Bool {
        let materials = materials(for: renderable)
        let hasOpaque = materials.contains { $0.blending == .disabled }
        let hasAlphaTransparent = materials.contains { usesAlphaOit($0) }
        let hasClassicTransparent = materials.contains {
            $0.blending != .disabled && !usesAlphaOit($0)
        }
        let hasSurfaceOpaque = materials.contains {
            $0.lightingModel == .surface && $0.blending == .disabled
        }
        let hasUnlitOpaque = materials.contains {
            $0.lightingModel == .unlit && $0.blending == .disabled
        }

        switch route {
        case .opaque:
            return hasOpaque
        case .alphaTransparent:
            return hasAlphaTransparent
        case .classicTransparent:
            return hasClassicTransparent
        case .surfaceOpaque:
            return hasSurfaceOpaque
        case .unlitOpaque:
            return hasUnlitOpaque
        }
    }

    private func routePassEntries(route: RenderRoute) -> [RenderRouteEntry] {
        let renderListLayers = Set(renderLists.keys)
        let commandLayers = Set(scheduledCurrentPassEncodingCommands.map(\.renderLayer))
        let layers = renderListLayers.union(commandLayers).sorted()

        return layers
            .enumerated()
            .compactMap { pass, renderLayer in
                let renderables = renderLists[renderLayer]?
                    .getRenderables(sorted: sortObjects)
                    .filter { shouldRender($0, route: route) } ?? []
                let commands = scheduledCurrentPassEncodingCommands.filter {
                    $0.renderLayer == renderLayer &&
                        $0.routeRenderables.contains { shouldRender($0, route: route) }
                }

                guard !renderables.isEmpty || !commands.isEmpty else { return nil }
                return RenderRouteEntry(
                    pass: pass,
                    renderables: renderables,
                    commands: commands
                )
            }
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
        let key = RenderContextKey(
            renderingMode: mode,
            activeOutputs: outputs,
            alphaOitEnabled: alphaOitEnabled,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat
        )

        if let renderContext = renderContextCache[key] {
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

        renderContextCache[key] = renderContext
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

    private func prepareDeferredLightingMaterial(camera: Camera) {
        deferredLightingMaterial.albedoTexture = albedoTexture
        deferredLightingMaterial.normalTexture = normalTexture
        deferredLightingMaterial.pbrTexture = pbrTexture
        deferredLightingMaterial.emissiveTexture = emissiveTexture
        deferredLightingMaterial.depthTexture = depthTexture

        deferredLightingMaterial.lightCount = lightList.count
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
        deferredLightingMaterial.update(camera: camera)
    }

    @discardableResult
    private func encodeDeferredLightingPass(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        sceneCamera: Camera,
        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        colorStoreAction: MTLStoreAction,
        unlitEntries: [RenderRouteEntry] = [],
        unlitCameras: [Camera] = [],
        finalDepthStoreAction: MTLStoreAction = .dontCare,
        finalStencilStoreAction: MTLStoreAction = .dontCare
    ) -> Bool {
        guard albedoTexture != nil,
              normalTexture != nil,
              pbrTexture != nil,
              emissiveTexture != nil,
              depthTexture != nil
        else { return false }

        prepareDeferredLightingMaterial(camera: sceneCamera)
        deferredLightingCamera.update()
        deferredLightingMesh.update()
        deferredLightingMesh.encode(commandBuffer)

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

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return false
        }

        renderEncoder.label = "\(self.label) Deferred Lighting Resolve"
#if DEBUG
        renderEncoder.pushDebugGroup("Deferred Lighting Resolve")
#endif
        renderEncoder.setViewports(viewports)

        if context.vertexAmplificationCount > 1 {
            var maps = viewMappings
            if maps.isEmpty {
                maps = (0..<context.vertexAmplificationCount).map {
                    .init(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0))
                }
            }
            renderEncoder.setVertexAmplificationCount(context.vertexAmplificationCount, viewMappings: &maps)
        }

        let deferredCameras = Array(repeating: deferredLightingCamera, count: max(context.vertexAmplificationCount, 1))
        encode(
            renderEncoder: renderEncoder,
            pass: 0,
            renderables: [deferredLightingMesh],
            cameras: deferredCameras,
            viewports: simdViewports,
            phase: .unlitOpaque
        )

        if let firstEntry = unlitEntries.first {
#if DEBUG
            renderEncoder.pushDebugGroup("Unlit Forward Pass \(firstEntry.pass)")
#endif
            encode(
                renderEncoder: renderEncoder,
                pass: firstEntry.pass,
                renderables: firstEntry.renderables,
                commands: firstEntry.commands,
                cameras: unlitCameras,
                viewports: simdViewports,
                phase: .unlitOpaque
            )
#if DEBUG
            renderEncoder.popDebugGroup()
#endif
        }

#if DEBUG
        renderEncoder.popDebugGroup()
#endif
        renderEncoder.endEncoding()

        // Encode any additional unlit render passes (multiple render layers, uncommon case).
        for (i, entry) in unlitEntries.dropFirst().enumerated() {
            let isFinal = i == unlitEntries.count - 2
            renderPassDescriptor.colorAttachments[0].loadAction = .load
            renderPassDescriptor.depthAttachment.loadAction = .load
            renderPassDescriptor.stencilAttachment.loadAction = .load
            renderPassDescriptor.colorAttachments[0].storeAction = isFinal ? colorStoreAction : .store
            renderPassDescriptor.depthAttachment.storeAction = isFinal ? finalDepthStoreAction : .store
            renderPassDescriptor.stencilAttachment.storeAction = isFinal ? finalStencilStoreAction : .store

            guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { continue }
            enc.label = "\(self.label) Unlit Forward Pass \(entry.pass)"
#if DEBUG
            enc.pushDebugGroup("Unlit Forward Pass \(entry.pass)")
#endif
            enc.setViewports(viewports)
            if context.vertexAmplificationCount > 1 {
                var maps = viewMappings
                if maps.isEmpty {
                    maps = (0..<context.vertexAmplificationCount).map {
                        .init(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0))
                    }
                }
                enc.setVertexAmplificationCount(context.vertexAmplificationCount, viewMappings: &maps)
            }
            encode(
                renderEncoder: enc,
                pass: entry.pass,
                renderables: entry.renderables,
                commands: entry.commands,
                cameras: unlitCameras,
                viewports: simdViewports,
                phase: .unlitOpaque
            )
#if DEBUG
            enc.popDebugGroup()
#endif
            enc.endEncoding()
        }

        return true
    }

    private func shouldEncodeEmptyPass(renderPassDescriptor: MTLRenderPassDescriptor, auxiliaryAttachmentIndices: [Int]) -> Bool {
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
        for entry in routeEntries {
            let renderables = entry.renderables + entry.commands.flatMap(\.routeRenderables)
            for renderable in renderables {
                let renderContext = renderContext(for: renderable, phase: .alphaTransparent)
                for material in materials(for: renderable) where usesAlphaOit(material) {
                    if let pipeline = material.getPipeline(renderContext: renderContext, shadow: false) {
                        return pipeline.imageblockSampleLength
                    }
                }
            }
        }
        return nil
    }

    @discardableResult
    private func encodeAlphaOitRoute(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        cameras: [Camera],
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

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return false
            }

            renderEncoder.label = "\(self.label) Alpha OIT Pass"
#if DEBUG
            renderEncoder.pushDebugGroup("Alpha OIT Pass")
#endif
            renderEncoder.setViewports(viewports)

            if context.vertexAmplificationCount > 1 {
                var maps = viewMappings
                if maps.isEmpty {
                    maps = (0..<context.vertexAmplificationCount).map {
                        .init(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0))
                    }
                }
                renderEncoder.setVertexAmplificationCount(context.vertexAmplificationCount, viewMappings: &maps)
            }

#if DEBUG
            renderEncoder.pushDebugGroup("Alpha OIT Tile Init")
#endif
            renderEncoder.setRenderPipelineState(resources.tilePipeline)
            renderEncoder.dispatchThreadsPerTile(alphaOitTileSize)
#if DEBUG
            renderEncoder.popDebugGroup()
#endif

            for entry in routeEntries {
#if DEBUG
                renderEncoder.pushDebugGroup("Alpha OIT Geometry Pass \(entry.pass)")
#endif
                encode(
                    renderEncoder: renderEncoder,
                    pass: entry.pass,
                    renderables: entry.renderables,
                    commands: entry.commands,
                    cameras: cameras,
                    viewports: simdViewports,
                    phase: .alphaTransparent
                )
#if DEBUG
                renderEncoder.popDebugGroup()
#endif
            }

#if DEBUG
            renderEncoder.pushDebugGroup("Alpha OIT Blend")
#endif
            renderEncoder.setRenderPipelineState(resources.blendPipeline)
            renderEncoder.setDepthStencilState(resources.blendDepthStencilState)
            renderEncoder.setCullMode(.none)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
#if DEBUG
            renderEncoder.popDebugGroup()
            renderEncoder.popDebugGroup()
#endif
            renderEncoder.endEncoding()

            return true
        } catch {
            print("\(label) Alpha OIT: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func encodeEntries(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        entries: [RenderRouteEntry],
        phase: MaterialPassType,
        label: String,
        cameras: [Camera],
        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        clearWhenEmpty: Bool
    ) -> Bool {
        let originalColorStoreAction = renderPassDescriptor.colorAttachments[0].storeAction
        let originalDepthStoreAction = renderPassDescriptor.depthAttachment.storeAction
        let originalStencilStoreAction = renderPassDescriptor.stencilAttachment.storeAction

        if entries.isEmpty {
            guard clearWhenEmpty,
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else { return false }

            renderEncoder.label = label + " Empty Pass"
            renderEncoder.setViewports(viewports)
            renderEncoder.endEncoding()
            return true
        }

        for (index, entry) in entries.enumerated() {
            let isFinalEntry = index == entries.count - 1
            if index > 0 {
                renderPassDescriptor.colorAttachments[0].loadAction = .load
                renderPassDescriptor.depthAttachment.loadAction = .load
                renderPassDescriptor.stencilAttachment.loadAction = .load
            }

            renderPassDescriptor.colorAttachments[0].storeAction = isFinalEntry ? originalColorStoreAction : .store
            renderPassDescriptor.depthAttachment.storeAction = isFinalEntry ? originalDepthStoreAction : .store
            renderPassDescriptor.stencilAttachment.storeAction = isFinalEntry ? originalStencilStoreAction : .store

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { continue }
            renderEncoder.label = "\(self.label) \(label) Pass \(entry.pass)"
            renderEncoder.setViewports(viewports)

            if context.vertexAmplificationCount > 1 {
                var maps = viewMappings
                if maps.isEmpty {
                    maps = (0..<context.vertexAmplificationCount).map {
                        .init(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0))
                    }
                }
                renderEncoder.setVertexAmplificationCount(context.vertexAmplificationCount, viewMappings: &maps)
            }

            encode(
                renderEncoder: renderEncoder,
                pass: entry.pass,
                renderables: entry.renderables,
                commands: entry.commands,
                cameras: cameras,
                viewports: simdViewports,
                phase: phase
            )
            renderEncoder.endEncoding()
        }

        return true
    }

    @discardableResult
    private func encodeRoute(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        route: RenderRoute,
        phase: MaterialPassType,
        label: String,
        cameras: [Camera],
        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        auxiliaryAttachmentIndices: [Int],
        clearWhenEmpty: Bool
    ) -> Bool {
        let routeEntries = routePassEntries(route: route)
        let originalColorStoreAction = renderPassDescriptor.colorAttachments[0].storeAction
        let originalDepthStoreAction = renderPassDescriptor.depthAttachment.storeAction
        let originalStencilStoreAction = renderPassDescriptor.stencilAttachment.storeAction

        if routeEntries.isEmpty {
            guard clearWhenEmpty,
                  shouldEncodeEmptyPass(renderPassDescriptor: renderPassDescriptor, auxiliaryAttachmentIndices: auxiliaryAttachmentIndices),
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else { return false }

            renderEncoder.label = label + " Empty Pass"
#if DEBUG
            renderEncoder.pushDebugGroup(label + " Empty Pass")
#endif
            renderEncoder.setViewports(viewports)
#if DEBUG
            renderEncoder.popDebugGroup()
#endif
            renderEncoder.endEncoding()
            return true
        }

        for (index, entry) in routeEntries.enumerated() {
            let isFinalEntry = index == routeEntries.count - 1
            if index > 0 {
                renderPassDescriptor.colorAttachments[0].loadAction = .load
                renderPassDescriptor.depthAttachment.loadAction = .load
                renderPassDescriptor.stencilAttachment.loadAction = .load
                for attachmentIndex in auxiliaryAttachmentIndices {
                    colorAttachment(renderPassDescriptor, index: attachmentIndex)?.loadAction = .load
                }
            }

            renderPassDescriptor.colorAttachments[0].storeAction = isFinalEntry ? originalColorStoreAction : .store
            renderPassDescriptor.depthAttachment.storeAction = isFinalEntry ? originalDepthStoreAction : .store
            renderPassDescriptor.stencilAttachment.storeAction = isFinalEntry ? originalStencilStoreAction : .store

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { continue }

            renderEncoder.label = "\(self.label) \(label) Pass \(entry.pass)"
#if DEBUG
            renderEncoder.pushDebugGroup("\(label) Pass \(entry.pass)")
#endif
            renderEncoder.setViewports(viewports)

            if context.vertexAmplificationCount > 1 {
                var maps = viewMappings
                if maps.isEmpty {
                    maps = (0..<context.vertexAmplificationCount).map {
                        .init(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0))
                    }
                }
                renderEncoder.setVertexAmplificationCount(context.vertexAmplificationCount, viewMappings: &maps)
            }

            encode(
                renderEncoder: renderEncoder,
                pass: entry.pass,
                renderables: entry.renderables,
                commands: entry.commands,
                cameras: cameras,
                viewports: simdViewports,
                phase: phase
            )

#if DEBUG
            renderEncoder.popDebugGroup()
#endif
            renderEncoder.endEncoding()
        }

        return true
    }

    @discardableResult
    private func encodeMainRenderPasses(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        cameras: [Camera],
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
            let opaqueEncoded = encodeRoute(
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                route: .opaque,
                phase: .forwardOpaque,
                label: "Forward Opaque",
                cameras: cameras,
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
                let alphaEncoded = encodeAlphaOitRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    cameras: cameras,
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
                let transparentEncoded = encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    route: .classicTransparent,
                    phase: .classicTransparent,
                    label: "Classic Transparent Forward",
                    cameras: cameras,
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
            let needsSurfacePass = hasSurfaceOpaqueRenderables || usesAuxiliaryAttachments || (!hasUnlitOpaqueRenderables && !hasTransparentRenderables && renderLists.isEmpty)
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
                didEncode = encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    route: .surfaceOpaque,
                    phase: .surfaceOpaque,
                    label: "Surface MRT",
                    cameras: cameras,
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
                let unlitEncoded = encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    route: .unlitOpaque,
                    phase: .unlitOpaque,
                    label: "Opaque Unlit Forward",
                    cameras: cameras,
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
                    let alphaEncoded = encodeAlphaOitRoute(
                        renderPassDescriptor: renderPassDescriptor,
                        commandBuffer: commandBuffer,
                        cameras: cameras,
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
                    let transparentEncoded = encodeRoute(
                        renderPassDescriptor: renderPassDescriptor,
                        commandBuffer: commandBuffer,
                        route: .classicTransparent,
                        phase: .classicTransparent,
                        label: "Classic Transparent Forward",
                        cameras: cameras,
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
                return encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    route: .surfaceOpaque,
                    phase: .surfaceOpaque,
                    label: "Empty",
                    cameras: cameras,
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
            let needsSurfacePass = hasSurfaceOpaqueRenderables || usesAuxiliaryAttachments || (opaqueUnlitEntries.isEmpty && !hasTransparentRenderables && renderLists.isEmpty)
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
                let surfaceEncoded = encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    route: .surfaceOpaque,
                    phase: .surfaceOpaque,
                    label: "Deferred Geometry",
                    cameras: cameras,
                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    auxiliaryAttachmentIndices: auxiliaryAttachmentIndices,
                    clearWhenEmpty: true
                )
                let resolveEncoded = encodeDeferredLightingPass(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    sceneCamera: cameras[0],
                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    colorStoreAction: hasTransparentRenderables ? .store : finalColorStoreAction,
                    unlitEntries: opaqueUnlitEntries,
                    unlitCameras: cameras,
                    finalDepthStoreAction: hasTransparentRenderables ? .store : finalDepthStoreAction,
                    finalStencilStoreAction: hasTransparentRenderables ? .store : finalStencilStoreAction
                )
                didEncode = surfaceEncoded || resolveEncoded

                // G-buffer textures weren't available (encodeDeferredLightingPass returned false)
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
                    let unlitFallbackEncoded = encodeRoute(
                        renderPassDescriptor: renderPassDescriptor,
                        commandBuffer: commandBuffer,
                        route: .unlitOpaque,
                        phase: .unlitOpaque,
                        label: "Opaque Unlit Fallback",
                        cameras: cameras,
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
                    let unlitEncoded = encodeRoute(
                        renderPassDescriptor: renderPassDescriptor,
                        commandBuffer: commandBuffer,
                        route: .unlitOpaque,
                        phase: .unlitOpaque,
                        label: "Opaque Unlit Forward",
                        cameras: cameras,
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
                    let alphaEncoded = encodeAlphaOitRoute(
                        renderPassDescriptor: renderPassDescriptor,
                        commandBuffer: commandBuffer,
                        cameras: cameras,
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
                    let transparentEncoded = encodeRoute(
                        renderPassDescriptor: renderPassDescriptor,
                        commandBuffer: commandBuffer,
                        route: .classicTransparent,
                        phase: .classicTransparent,
                        label: "Classic Transparent Forward",
                        cameras: cameras,
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

    private func update(commandBuffer: MTLCommandBuffer, scene: Object, cameras: [Camera], viewports: [simd_float4]) {
        for camera in cameras {
            camera.update()
        }

        onUpdate?()

        objectList.removeAll(keepingCapacity: true)
        renderLists.removeAll(keepingCapacity: true)

        lightList.removeAll(keepingCapacity: true)
        lightReceivers.removeAll(keepingCapacity: true)

        shadowCasters.removeAll(keepingCapacity: true)
        shadowReceivers.removeAll(keepingCapacity: true)

        updateLists(
            object: scene,
            visible: true
        )

        updateScene(
            commandBuffer: commandBuffer,
            cameras: cameras,
            viewports: viewports
        )

        updateLights()
    }

    private func updateLists(object: Object, visible: Bool) {
        object.update()

        if object.visible, visible {
            objectList.append(object)

            if let light = object as? Light {
                light.shadowIndex = -1
                light.projectorIndex = -1
                lightList.append(light)
            }

            if let renderable = object as? Renderable {
                if let renderPassList = renderLists[renderable.renderLayer.rawValue] {
                    renderPassList.append(renderable)
                } else {
                    renderLists[renderable.renderLayer.rawValue] = RenderList(renderable)
                }

                if renderable.lighting {
                    lightReceivers.append(renderable)
                }

                if renderable.receiveShadow {
                    shadowReceivers.append(renderable)
                }

                if renderable.castShadow {
                    shadowCasters.append(renderable)
                }
            }
            
            for child in object.children {
                updateLists(
                    object: child,
                    visible: object.visible && visible
                )
            }
        }
    }

    private func updateScene(commandBuffer: MTLCommandBuffer, cameras: [Camera], viewports: [simd_float4]) {
        updateDirectLightingState()

        let lightCount = lightList.count
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

        for object in objectList {
            if let environment = object as? IBLEnvironment {
                activeEnvironmentIntensity = environment.environmentIntensity
                cubemapTexture = environment.cubemapTexture

                activeReflectionTexture = environment.reflectionTexture
                activeReflectionTexcoordTransform = environment.reflectionTexcoordTransform

                activeIrradianceTexture = environment.irradianceTexture
                activeIrradianceTexcoordTransform = environment.irradianceTexcoordTransform

                activeBrdfTexture = environment.brdfTexture
            }

            if let renderable = object as? Renderable {
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

                    if material.lighting, renderable.receiveShadow, !usesDeferredResolve {
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

                    material.update()
                }
            } else {
                for i in 0..<context.vertexAmplificationCount {
                    object.update(
                        renderContext: context,
                        camera: cameras[i],
                        viewport: viewports[i],
                        index: i
                    )
                }
            }

            object.encode(commandBuffer)
        }
    }

    // MARK: - Internal Encoding

    private func encode(
        renderEncoder: MTLRenderCommandEncoder,
        pass: Int,
        renderables: [Renderable],
        commands: [ScheduledCurrentPassEncodingCommand] = [],
        cameras: [Camera],
        viewports: [simd_float4],
        phase: MaterialPassType,
        overrideMaterial: Material? = nil
    ) {
        let renderEncoderState = RenderEncoderState(renderEncoder: renderEncoder)
        let previousEncodePass = currentEncodePass
        currentEncodePass = CurrentEncodePass(
            cameras: cameras,
            viewports: viewports,
            phase: phase,
            overrideMaterial: overrideMaterial
        )
        defer {
            currentEncodePass = previousEncodePass
        }

        if !lightReceivers.isEmpty {
            if let lightBuffer = lightDataBuffer {
                renderEncoder.setFragmentBuffer(
                    lightBuffer.buffer,
                    offset: lightBuffer.offset,
                    index: FragmentBufferIndex.Lighting.rawValue
                )
            }
        }

        if let projectorMatricesBuffer = projectorMatricesBuffer {
            renderEncoder.setFragmentBuffer(
                projectorMatricesBuffer.buffer,
                offset: projectorMatricesBuffer.offset,
                index: FragmentBufferIndex.ProjectorMatrices.rawValue
            )
        }

        if let projectorTransformsBuffer = projectorTransformsBuffer {
            renderEncoder.setFragmentBuffer(
                projectorTransformsBuffer.buffer,
                offset: projectorTransformsBuffer.offset,
                index: FragmentBufferIndex.ProjectorTransforms.rawValue
            )
        }

        if let directShadowDataBuffer = directShadowDataBuffer {
            renderEncoder.setFragmentBuffer(
                directShadowDataBuffer.buffer,
                offset: directShadowDataBuffer.offset,
                index: FragmentBufferIndex.DirectShadows.rawValue
            )
        }

        if let directShadowMatricesBuffer = directShadowMatricesBuffer {
            renderEncoder.setFragmentBuffer(
                directShadowMatricesBuffer.buffer,
                offset: directShadowMatricesBuffer.offset,
                index: FragmentBufferIndex.DirectShadowMatrices.rawValue
            )
        }

        updateDirectShadowTextures()
        updateProjectorTextures()

        if !projectorTextures.isEmpty {
            renderEncoder.setFragmentTextures(
                projectorTextures,
                range: FragmentTextureIndex.Projector0.rawValue..<(FragmentTextureIndex.Projector0.rawValue + projectorTextures.count)
            )
        }

        if !directShadowTextures.isEmpty {
            renderEncoder.setFragmentTextures(
                directShadowTextures,
                range: FragmentTextureIndex.DirectShadow0.rawValue..<(FragmentTextureIndex.DirectShadow0.rawValue + directShadowTextures.count)
            )
        }
        if let projectorMatricesBuffer = projectorMatricesBuffer {
            renderEncoder.useResource(projectorMatricesBuffer.buffer, usage: .read, stages: .fragment)
        }

        if let projectorTransformsBuffer = projectorTransformsBuffer {
            renderEncoder.useResource(projectorTransformsBuffer.buffer, usage: .read, stages: .fragment)
        }

        if let directShadowDataBuffer = directShadowDataBuffer {
            renderEncoder.useResource(directShadowDataBuffer.buffer, usage: .read, stages: .fragment)
        }

        if let directShadowMatricesBuffer = directShadowMatricesBuffer {
            renderEncoder.useResource(directShadowMatricesBuffer.buffer, usage: .read, stages: .fragment)
        }

        for projectorTexture in projectorTextures {
            if let projectorTexture {
                renderEncoder.useResource(projectorTexture, usage: .read, stages: .fragment)
            }
        }

        for directShadowTexture in directShadowTextures {
            if let directShadowTexture {
                renderEncoder.useResource(directShadowTexture, usage: .read, stages: .fragment)
            }
        }

        for renderable in renderables {
            let drawContext = overrideMaterial?.context ?? renderContext(for: renderable, phase: phase)
            if renderable.vertexUniforms[drawContext.id] == nil {
                renderable.ensureVertexUniformBuffer(context: drawContext)
            }
            guard renderable.isDrawable(renderContext: drawContext, shadow: false) else { continue }
            _encode(
                renderEncoder: renderEncoder,
                renderEncoderState: renderEncoderState,
                renderable: renderable,
                cameras: cameras,
                viewports: viewports,
                phase: phase,
                overrideMaterial: overrideMaterial
            )
        }

        for command in commands {
            command.encode(renderEncoderState)
        }
    }

    private func _encode(
        renderEncoder: MTLRenderCommandEncoder,
        renderEncoderState: RenderEncoderState,
        renderable: Renderable,
        cameras: [Camera],
        viewports: [simd_float4],
        phase: MaterialPassType,
        overrideMaterial: Material? = nil
    ) {
#if DEBUG
        renderEncoder.pushDebugGroup(renderable.label)
#endif
        let savedMaterial = renderable.material
        // Determine which context to use for pipeline/uniform lookups
        let renderContext = overrideMaterial?.context ?? renderContext(for: renderable, phase: phase)
        let savedMaterialPass = renderable.materialPass

        switch phase {
        case .forwardOpaque:
            renderable.materialPass = .opaque
        case .alphaTransparent:
            renderable.materialPass = .alphaTransparent
        case .classicTransparent:
            renderable.materialPass = .classicTransparent
        case .surfaceOpaque:
            renderable.materialPass = .surfaceOpaque
        case .unlitOpaque:
            renderable.materialPass = .unlitOpaque
        }

        if let overrideMaterial {
            renderable.material = overrideMaterial
        }
        defer {
            renderable.materialPass = savedMaterialPass
            if overrideMaterial != nil {
                renderable.material = savedMaterial
            }
        }

        for i in 0..<context.vertexAmplificationCount {
            renderable.update(
                renderContext: renderContext,
                camera: cameras[i],
                viewport: viewports[i],
                index: i
            )
        }

        renderable.preDraw?(renderEncoder)

        renderEncoderState.windingOrder = renderable.windingOrder
        renderEncoderState.triangleFillMode = renderable.triangleFillMode

        if renderable.doubleSided, renderable.cullMode == .none, renderable.opaque == false {
            renderEncoderState.cullMode = .front
            renderable.draw(
                renderContext: renderContext,
                renderEncoderState: renderEncoderState,
                shadow: false
            )

            renderEncoderState.cullMode = .back
            renderable.draw(
                renderContext: renderContext,
                renderEncoderState: renderEncoderState,
                shadow: false
            )
        } else {
            renderEncoderState.cullMode = renderable.cullMode
            renderable.draw(
                renderContext: renderContext,
                renderEncoderState: renderEncoderState,
                shadow: false
            )
        }

#if DEBUG
        renderEncoder.popDebugGroup()
#endif
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

    private func updateLights() {
        setupLightDataBuffer()
        updateLightDataBuffer()
    }

    private func setupLightDataBuffer() {
        guard lightList.count != lightDataBuffer?.count else { return }
        lightDataSubscriptions.removeAll(keepingCapacity: true)

        if lightList.isEmpty {
            lightDataBuffer = nil
        } else {
            for light in lightList {
                light.publisher.sink { [weak self] _ in
                    self?._updateLightDataBuffer = true
                }.store(in: &lightDataSubscriptions)
            }
            lightDataBuffer = StructBuffer<LightData>(
                device: context.device,
                count: lightList.count,
                label: "Light Data Buffer"
            )

            _updateLightDataBuffer = true
        }
    }

    private func updateLightDataBuffer() {
        guard let lightBuffer = lightDataBuffer, _updateLightDataBuffer else { return }

        lightBuffer.update(data: lightList.map { $0.data })

        _updateLightDataBuffer = false
    }

    private func updateDirectLightingState() {
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

        for light in lightList {
            light.shadowIndex = -1
            light.projectorIndex = -1

            if let spotLight = light as? SpotLight,
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

        if directShadowData.isEmpty {
            directShadowDataBuffer = nil
            directShadowMatricesBuffer = nil
        } else {
            if directShadowDataBuffer?.count != directShadowData.count {
                directShadowDataBuffer = StructBuffer<ShadowData>(
                    device: context.device,
                    count: directShadowData.count,
                    label: "Direct Shadow Data Buffer"
                )
            }

            if directShadowMatricesBuffer?.count != directShadowMatrices.count {
                directShadowMatricesBuffer = StructBuffer<simd_float4x4>(
                    device: context.device,
                    count: directShadowMatrices.count,
                    label: "Direct Shadow Matrices Buffer"
                )
            }

            directShadowDataBuffer?.update(data: directShadowData)
            directShadowMatricesBuffer?.update(data: directShadowMatrices)
        }

        if projectorMatrices.isEmpty {
            projectorMatricesBuffer = nil
            projectorTransformsBuffer = nil
        } else {
            if projectorMatricesBuffer?.count != projectorMatrices.count {
                projectorMatricesBuffer = StructBuffer<simd_float4x4>(
                    device: context.device,
                    count: projectorMatrices.count,
                    label: "Projector Matrices Buffer"
                )
            }

            if projectorTransformsBuffer?.count != projectorTransforms.count {
                projectorTransformsBuffer = StructBuffer<simd_float4x4>(
                    device: context.device,
                    count: projectorTransforms.count,
                    label: "Projector Transforms Buffer"
                )
            }

            projectorMatricesBuffer?.update(data: projectorMatrices)
            projectorTransformsBuffer?.update(data: projectorTransforms)
        }

        _updateLightDataBuffer = true
    }

    private func updateDirectShadowTextures() {
        directShadowTextures = directShadowLights.flatMap { light in
            light.shadow.textures.map(Optional.some)
        }
    }

    private func updateProjectorTextures() {
        projectorTextures = projectorLights.map(\.projectionTexture)
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
