//
//  Renderer.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Metal
import simd

open class Renderer {
    public var label = "Satin Renderer"

    public var onUpdate: (() -> Void)?

    public var sortObjects: Bool

    public let context: Context

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

    // MARK: - Renderer Outputs

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
        let colorPixelFormat: MTLPixelFormat
        let depthPixelFormat: MTLPixelFormat
        let stencilPixelFormat: MTLPixelFormat
    }

    private enum MaterialPassType {
        case forward
        case surface
        case unlit
    }

    private enum RenderRoute {
        case all
        case surface
        case unlit
    }

    private struct ColorAttachmentState {
        let texture: MTLTexture?
        let resolveTexture: MTLTexture?
        let loadAction: MTLLoadAction
        let storeAction: MTLStoreAction
        let clearColor: MTLClearColor
    }

    private struct RenderSubmission {
        let renderable: Renderable
        let state: RenderStateSnapshot
        let renderContext: Context
    }

    private var renderContextCache: [RenderContextKey: Context] = [:]

    private var objectList = [Object]()
    private var renderLists = [Int: RenderList]()

    private var lightList = [Light]()
    private var lightReceivers = [Renderable]()
    private var _updateLightDataBuffer = false
    private var lightDataBuffer: StructBuffer<LightData>?
    private var lightDataSubscriptions = Set<AnyCancellable>()

    private var shadowCasters = [Renderable]()
    private var shadowReceivers = [Renderable]()
    private var shadowList = [Shadow]()
    private var _updateShadowMatrices = false
    private var shadowMatricesBuffer: StructBuffer<simd_float4x4>?
    private var shadowMatricesSubscriptions = Set<AnyCancellable>()

//    to do: fix this so we actually listen to texture updates and update the arg encoder
    private var _updateShadowData = false
    private var _updateShadowTextures = false
    private var shadowArgumentEncoder: MTLArgumentEncoder?
    private var shadowArgumentBuffer: MTLBuffer?
    private var shadowDataBuffer: StructBuffer<ShadowData>?
    private var shadowTextureSubscriptions = Set<AnyCancellable>()
    private var shadowBufferSubscriptions = Set<AnyCancellable>()

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
        label: String = "Satin Renderer",
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
        self.label = label
        self.context = context
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
        let inAuxiliaryStates: [ColorAttachmentState] = (1...5).map { index in
            let attachment = renderPassDescriptor.colorAttachments[index]!
            return ColorAttachmentState(
                texture: attachment.texture,
                resolveTexture: attachment.resolveTexture,
                loadAction: attachment.loadAction,
                storeAction: attachment.storeAction,
                clearColor: attachment.clearColor
            )
        }

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

            for (offset, state) in inAuxiliaryStates.enumerated() {
                let attachment = renderPassDescriptor.colorAttachments[offset + 1]!
                attachment.texture = state.texture
                attachment.resolveTexture = state.resolveTexture
                attachment.loadAction = state.loadAction
                attachment.storeAction = state.storeAction
                attachment.clearColor = state.clearColor
            }
        }

        if context.colorPixelFormat == .invalid {
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

        if context.depthPixelFormat == .invalid {
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

            if context.depthPixelFormat == .depth32Float_stencil8 {
                renderPassDescriptor.stencilAttachment.texture = depthTexture
            }
        }

        if context.stencilPixelFormat != .invalid, context.depthPixelFormat != .depth32Float_stencil8 {
            if context.stencilPixelFormat == .invalid {
                renderPassDescriptor.stencilAttachment.texture = nil
                renderPassDescriptor.stencilAttachment.resolveTexture = nil
            } else if context.sampleCount > 1 {
                if inStencilTexture?.sampleCount != context.sampleCount {
                    setupStencilMultisampleTexture(arrayLength: arrayLength)
                    renderPassDescriptor.stencilAttachment.texture = stencilMultisampleTexture
                }

                if inStencilResolveTexture == nil {
                    setupStencilTexture(arrayLength: arrayLength)
                    renderPassDescriptor.depthAttachment.resolveTexture = stencilTexture
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
            if context.stencilPixelFormat != .invalid {
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
            if context.stencilPixelFormat != .invalid {
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

    private func shouldRender(_ materials: [Material], route: RenderRoute) -> Bool {
        let hasSurface = materials.contains { $0.lightingModel == .surface }
        let hasUnlit = materials.contains { $0.lightingModel == .unlit }

        switch route {
        case .all:
            return true
        case .surface:
            return hasSurface
        case .unlit:
            return hasUnlit && !hasSurface
        }
    }

    private func makeRenderSubmission(for renderable: Renderable, phase: MaterialPassType, materialsForRouting: [Material]) -> RenderSubmission {
        RenderSubmission(
            renderable: renderable,
            state: renderable.makeRenderStateSnapshot(),
            renderContext: renderContext(for: materialsForRouting, phase: phase)
        )
    }

    private func routePassEntries(route: RenderRoute, phase: MaterialPassType) -> [(pass: Int, submissions: [RenderSubmission])] {
        renderLists
            .sorted { $0.key < $1.key }
            .enumerated()
            .compactMap { pass, entry in
                let submissions = entry.value
                    .getRenderables(sorted: sortObjects)
                    .compactMap { renderable -> RenderSubmission? in
                        let materials = renderable.renderMaterialsForRouting()
                        guard shouldRender(materials, route: route) else {
                            return nil
                        }
                        return makeRenderSubmission(for: renderable, phase: phase, materialsForRouting: materials)
                    }
                return submissions.isEmpty ? nil : (pass, submissions)
            }
    }

    private func supportedOutputs(for materials: [Material], phase: MaterialPassType) -> RendererOutputs {
        switch phase {
        case .forward, .unlit:
            return [.color]
        case .surface:
            var outputs: RendererOutputs = [.color]
            for material in materials where material.lightingModel == .surface {
                outputs.formUnion(material.supportedOutputs.intersection(requestedOutputs))
            }
            return normalizedOutputs(outputs)
        }
    }

    private func renderContext(for materials: [Material], phase: MaterialPassType) -> Context {
        let mode: RenderingMode = phase == .surface ? renderingMode : .forward
        let outputs = supportedOutputs(for: materials, phase: phase)
        let key = RenderContextKey(
            renderingMode: mode,
            activeOutputs: outputs,
            colorPixelFormat: context.colorPixelFormat,
            depthPixelFormat: context.depthPixelFormat,
            stencilPixelFormat: context.stencilPixelFormat
        )

        if let renderContext = renderContextCache[key] {
            return renderContext
        }

        let renderContext = Context(
            device: context.device,
            sampleCount: context.sampleCount,
            colorPixelFormat: context.colorPixelFormat,
            depthPixelFormat: context.depthPixelFormat,
            stencilPixelFormat: context.stencilPixelFormat,
            vertexAmplificationCount: context.vertexAmplificationCount,
            maxBuffersInFlight: context.maxBuffersInFlight,
            renderingMode: mode,
            activeOutputs: outputs,
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
                "Satin Renderer auxiliary MRT outputs currently require sampleCount == 1."
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
            let attachment = renderPassDescriptor.colorAttachments[index]!
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
        unlitEntries: [(pass: Int, submissions: [RenderSubmission])] = [],
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
        let deferredSubmission = makeRenderSubmission(
            for: deferredLightingMesh,
            phase: .unlit,
            materialsForRouting: deferredLightingMesh.renderMaterialsForRouting()
        )
        encode(
            renderEncoder: renderEncoder,
            submissions: [deferredSubmission],
            cameras: deferredCameras,
            viewports: simdViewports
        )

        if let firstEntry = unlitEntries.first {
#if DEBUG
            renderEncoder.pushDebugGroup("Unlit Forward Pass \(firstEntry.pass)")
#endif
            encode(
                renderEncoder: renderEncoder,
                submissions: firstEntry.submissions,
                cameras: unlitCameras,
                viewports: simdViewports
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
            encode(renderEncoder: enc, submissions: entry.submissions, cameras: unlitCameras, viewports: simdViewports)
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
            let attachment = renderPassDescriptor.colorAttachments[index]!
            if attachment.texture != nil, attachment.loadAction == .clear {
                return true
            }
        }

        return false
    }

    @discardableResult
    private func encodeRoute(
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        entries: [(pass: Int, submissions: [RenderSubmission])],
        label: String,
        cameras: [Camera],
        viewports: [MTLViewport],
        simdViewports: [simd_float4],
        viewMappings: [MTLVertexAmplificationViewMapping],
        auxiliaryAttachmentIndices: [Int],
        clearWhenEmpty: Bool
    ) -> Bool {
        let originalColorStoreAction = renderPassDescriptor.colorAttachments[0].storeAction
        let originalDepthStoreAction = renderPassDescriptor.depthAttachment.storeAction
        let originalStencilStoreAction = renderPassDescriptor.stencilAttachment.storeAction

        if entries.isEmpty {
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

        for (index, entry) in entries.enumerated() {
            let isFinalEntry = index == entries.count - 1
            if index > 0 {
                renderPassDescriptor.colorAttachments[0].loadAction = .load
                renderPassDescriptor.depthAttachment.loadAction = .load
                renderPassDescriptor.stencilAttachment.loadAction = .load
                for attachmentIndex in auxiliaryAttachmentIndices {
                    renderPassDescriptor.colorAttachments[attachmentIndex]!.loadAction = .load
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
                submissions: entry.submissions,
                cameras: cameras,
                viewports: simdViewports
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
        let surfaceEntries = routePassEntries(route: .surface, phase: .surface)
        let unlitEntries = routePassEntries(route: .unlit, phase: .unlit)
        let hasSurfaceRenderables = !surfaceEntries.isEmpty
        let hasUnlitRenderables = !unlitEntries.isEmpty

        switch renderingMode {
        case .forward:
            configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
            return encodeRoute(
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                entries: routePassEntries(route: .all, phase: .forward),
                label: "Forward",
                cameras: cameras,
                viewports: viewports,
                simdViewports: simdViewports,
                viewMappings: viewMappings,
                auxiliaryAttachmentIndices: [],
                clearWhenEmpty: true
            )

        case .forwardPlus:
            let needsSurfacePass = hasSurfaceRenderables || usesAuxiliaryAttachments || (!hasUnlitRenderables && renderLists.isEmpty)
            var didEncode = false

            if needsSurfacePass {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: colorLoadAction,
                    depthLoadAction: depthLoadAction,
                    stencilLoadAction: stencilLoadAction,
                    colorStoreAction: hasUnlitRenderables ? .store : finalColorStoreAction,
                    depthStoreAction: hasUnlitRenderables ? .store : finalDepthStoreAction,
                    stencilStoreAction: hasUnlitRenderables ? .store : finalStencilStoreAction
                )
                let auxiliaryAttachmentIndices = configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor)
                didEncode = encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    entries: surfaceEntries,
                    label: renderingMode == .deferredGeometry ? "Deferred Geometry" : "Surface MRT",
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

            if hasUnlitRenderables {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: needsSurfacePass ? .load : colorLoadAction,
                    depthLoadAction: needsSurfacePass ? .load : depthLoadAction,
                    stencilLoadAction: needsSurfacePass ? .load : stencilLoadAction,
                    colorStoreAction: finalColorStoreAction,
                    depthStoreAction: finalDepthStoreAction,
                    stencilStoreAction: finalStencilStoreAction
                )
                configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)
                let unlitEncoded = encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    entries: unlitEntries,
                    label: "Unlit Forward",
                    cameras: cameras,
                    viewports: viewports,
                    simdViewports: simdViewports,
                    viewMappings: viewMappings,
                    auxiliaryAttachmentIndices: [],
                    clearWhenEmpty: !didEncode
                )
                didEncode = didEncode || unlitEncoded
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
                    entries: [],
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
            let needsSurfacePass = hasSurfaceRenderables || usesAuxiliaryAttachments || (unlitEntries.isEmpty && renderLists.isEmpty)
            var didEncode = false

            if needsSurfacePass {
                configureMainAttachments(
                    renderPassDescriptor: renderPassDescriptor,
                    colorLoadAction: colorLoadAction,
                    depthLoadAction: depthLoadAction,
                    stencilLoadAction: stencilLoadAction,
                    colorStoreAction: .dontCare,
                    depthStoreAction: .store,
                    stencilStoreAction: unlitEntries.isEmpty ? finalStencilStoreAction : .store
                )
                let auxiliaryAttachmentIndices = configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor)
                let surfaceEncoded = encodeRoute(
                    renderPassDescriptor: renderPassDescriptor,
                    commandBuffer: commandBuffer,
                    entries: surfaceEntries,
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
                    colorStoreAction: finalColorStoreAction,
                    unlitEntries: unlitEntries,
                    unlitCameras: cameras,
                    finalDepthStoreAction: finalDepthStoreAction,
                    finalStencilStoreAction: finalStencilStoreAction
                )
                didEncode = surfaceEncoded || resolveEncoded
            } else {
                configureAuxiliaryAttachments(renderPassDescriptor: renderPassDescriptor, enabled: false)

                // No surface/geometry pass but unlit objects still need to be rendered.
                if !unlitEntries.isEmpty {
                    configureMainAttachments(
                        renderPassDescriptor: renderPassDescriptor,
                        colorLoadAction: colorLoadAction,
                        depthLoadAction: depthLoadAction,
                        stencilLoadAction: stencilLoadAction,
                        colorStoreAction: finalColorStoreAction,
                        depthStoreAction: finalDepthStoreAction,
                        stencilStoreAction: finalStencilStoreAction
                    )
                    let unlitEncoded = encodeRoute(
                        renderPassDescriptor: renderPassDescriptor,
                        commandBuffer: commandBuffer,
                        entries: unlitEntries,
                        label: "Unlit Forward",
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

        shadowList.removeAll(keepingCapacity: true)
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
        updateShadows()
    }

    private func updateLists(object: Object, visible: Bool) {
        object.update()

        if object.visible, visible {
            objectList.append(object)

            if let light = object as? Light {
                light.shadowIndex = -1
                light.projectorIndex = -1
                lightList.append(light)
                if light.castShadow, light.shadow.isLegacyPlanarCompatible {
                    shadowList.append(light.shadow)
                }
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
        let shadowCount = shadowList.count
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
                    if material.lighting {
                        material.lightCount = lightCount
                        material.projectorCount = projectorCount
                    } else {
                        material.lightCount = 0
                        material.projectorCount = 0
                    }

                    if renderable.receiveShadow {
                        material.shadowCount = shadowCount
                    } else {
                        material.shadowCount = 0
                    }

                    if material.lighting, renderable.receiveShadow {
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
        submissions: [RenderSubmission],
        cameras: [Camera],
        viewports: [simd_float4]
    ) {
        let renderEncoderState = RenderEncoderState(renderEncoder: renderEncoder)

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
        
        // cache of old working code
        // but had a bug which Fabric seemed to trigger
        // causing a crash -
//        if !shadowReceivers.isEmpty {
//            for shadow in shadowList {
//                if let shadowTexture = shadow.texture {
//                    renderEncoder.useResource(shadowTexture, usage: .read, stages: .fragment)
//                }
//            }
//
//            if let shadowDataBuffer = shadowDataBuffer {
//                renderEncoder.useResource(shadowDataBuffer.buffer, usage: .read, stages: .fragment)
//            }
//
//            if let shadowBuffer = shadowMatricesBuffer {
//                renderEncoder.setVertexBuffer(
//                    shadowBuffer.buffer,
//                    offset: shadowBuffer.offset,
//                    index: VertexBufferIndex.ShadowMatrices.rawValue
//                )
//            }
//
//            if let shadowArgumentBuffer = shadowArgumentBuffer {
//                renderEncoder.setFragmentBuffer(
//                    shadowArgumentBuffer,
//                    offset: 0,
//                    index: FragmentBufferIndex.Shadows.rawValue
//                )
//            }
//        }
        
        // This fixes a crash only in Fabric
        // (at least, i couldnt trigger it in Satin's Examples)

        // Do not gate shadow buffer bindings on `shadowReceivers`.
        // Shader variants for Physical / Standard materials may still expect
        // `shadowMatrices` (vertex index) and `shadows` (fragment index) even
        // in frames where no objects currently receive shadows.
        //
        // If the shadow buffers exist (created when at least one shadow-casting
        // light is active), they *must always* be bound to their expected buffer
        // indices to satisfy the pipeline’s argument layout. Failing to bind them
        // results in Metal validation errors such as:
        //
        //   missing buffer binding at index 4 for shadowMatrices[0]
        //   missing buffer binding at index 3 for shadows[0]
        //
        // We therefore bind the shadow buffers whenever they are non-nil,
        // regardless of how many receivers are present this frame.
        
        if let shadowBuffer = shadowMatricesBuffer {
            // Always bind shadow matrices if we have a buffer
            renderEncoder.setVertexBuffer(
                shadowBuffer.buffer,
                offset: shadowBuffer.offset,
                index: VertexBufferIndex.ShadowMatrices.rawValue
            )
        }

        if let shadowArgumentBuffer = shadowArgumentBuffer {
            // Always bind shadow argument buffer if we have one
            renderEncoder.setFragmentBuffer(
                shadowArgumentBuffer,
                offset: 0,
                index: FragmentBufferIndex.Shadows.rawValue
            )
        }

        // The useResource bits are only really needed when we *actually* have shadows;
        // they don’t matter for the binding assertion.
        if !shadowList.isEmpty {
            for shadow in shadowList {
                if let shadowTexture = shadow.texture {
                    renderEncoder.useResource(shadowTexture, usage: .read, stages: .fragment)
                }
            }

            if let shadowDataBuffer = shadowDataBuffer {
                renderEncoder.useResource(shadowDataBuffer.buffer, usage: .read, stages: .fragment)
            }
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

        for submission in submissions {
            let renderable = submission.renderable
            let drawContext = submission.renderContext
            if renderable.vertexUniforms[drawContext.id] == nil {
                renderable.vertexUniforms[drawContext.id] = VertexUniformBuffer(context: drawContext)
            }
            guard renderable.isDrawable(renderContext: drawContext, shadow: false) else { continue }
            _encode(
                renderEncoder: renderEncoder,
                renderEncoderState: renderEncoderState,
                submission: submission,
                cameras: cameras,
                viewports: viewports
            )
        }
    }

    private func _encode(
        renderEncoder: MTLRenderCommandEncoder,
        renderEncoderState: RenderEncoderState,
        submission: RenderSubmission,
        cameras: [Camera],
        viewports: [simd_float4]
    ) {
        let renderable = submission.renderable
#if DEBUG
        renderEncoder.pushDebugGroup(renderable.label)
#endif
        let renderContext = submission.renderContext
        let state = submission.state

        for i in 0..<context.vertexAmplificationCount {
            renderable.update(
                renderContext: renderContext,
                camera: cameras[i],
                viewport: viewports[i],
                index: i
            )
        }

        renderable.preDraw?(renderEncoder)

        renderEncoderState.windingOrder = state.windingOrder
        renderEncoderState.triangleFillMode = state.triangleFillMode

        if state.doubleSided, state.cullMode == .none, !state.opaque {
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
            renderEncoderState.cullMode = state.cullMode
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
        guard updateColorTexture, context.colorPixelFormat != .invalid, size.width > 1, size.height > 1 else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: context.colorPixelFormat,
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
              context.colorPixelFormat != .invalid,
              context.sampleCount > 1,
              size.width > 0,
              size.height > 0
        else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: context.colorPixelFormat,
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
              context.depthPixelFormat != .invalid,
              (depthLoadAction != .dontCare && depthStoreAction != .dontCare),
              size.width > 0,
              size.height > 0
        else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: context.depthPixelFormat,
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
              context.depthPixelFormat != .invalid,
              (depthLoadAction != .dontCare && depthStoreAction != .dontCare),

              context.sampleCount > 1,
              size.width > 0,
              size.height > 0
        else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: context.depthPixelFormat,
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
              context.stencilPixelFormat != .invalid,
              (stencilLoadAction != .dontCare && stencilStoreAction != .dontCare),
              size.width > 1,
              size.height > 1
        else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = context.stencilPixelFormat
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
              context.stencilPixelFormat != .invalid,
              (stencilLoadAction != .dontCare && stencilStoreAction != .dontCare),
              context.sampleCount > 1,
              size.width > 0,
              size.height > 0 else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = context.stencilPixelFormat
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

    // MARK: - Shadows

    private func updateShadows() {
        setupShadows()
        updateShadowMatrices()
        updateShadowData()
        updateShadowTextures()
    }

    private func setupShadows() {
        guard shadowList.count != shadowMatricesBuffer?.count else { return }

        shadowMatricesSubscriptions.removeAll(keepingCapacity: true)
        shadowTextureSubscriptions.removeAll(keepingCapacity: true)
        shadowBufferSubscriptions.removeAll(keepingCapacity: true)

        if shadowList.isEmpty {
            shadowMatricesBuffer = nil
            shadowArgumentEncoder = nil
            shadowArgumentBuffer = nil

        } else {
            shadowMatricesBuffer = StructBuffer<simd_float4x4>(
                device: context.device,
                count: shadowList.count,
                label: "Shadow Matrices Buffer"
            )

            for light in lightList where light.castShadow && light.shadow.isLegacyPlanarCompatible {
                light.publisher.sink { [weak self] _ in
                    self?._updateShadowMatrices = true
                }.store(in: &shadowMatricesSubscriptions)
            }

            _updateShadowMatrices = true

            let strengthsArg = MTLArgumentDescriptor()
            strengthsArg.index = FragmentBufferIndex.ShadowData.rawValue
            strengthsArg.access = .readOnly
            strengthsArg.dataType = .pointer

            let texturesArg = MTLArgumentDescriptor()
            texturesArg.index = FragmentTextureIndex.Shadow0.rawValue
            texturesArg.access = .readOnly
            texturesArg.arrayLength = shadowList.count
            texturesArg.dataType = .texture
            texturesArg.textureType = .type2D

            if let shadowArgumentEncoder = context.device.makeArgumentEncoder(arguments: [strengthsArg, texturesArg]) {
                let shadowArgumentBuffer = context.device.makeBuffer(length: shadowArgumentEncoder.encodedLength, options: .storageModeShared)
                shadowArgumentBuffer?.label = "Shadow Argument Buffer"
                shadowArgumentEncoder.setArgumentBuffer(shadowArgumentBuffer, offset: 0)

                let shadowDataBuffer = StructBuffer<ShadowData>(
                    device: context.device,
                    count: shadowList.count,
                    label: "Shadow Data Buffer"
                )

                self.shadowArgumentBuffer = shadowArgumentBuffer
                self.shadowArgumentEncoder = shadowArgumentEncoder
                self.shadowDataBuffer = shadowDataBuffer

                shadowArgumentEncoder.setBuffer(shadowDataBuffer.buffer, offset: shadowDataBuffer.offset, index: FragmentBufferIndex.ShadowData.rawValue)

                for (index, shadow) in shadowList.enumerated() {
                    shadowArgumentEncoder.setTexture(shadow.textures.first, index: FragmentTextureIndex.Shadow0.rawValue + index)
                }
            }

            for shadow in shadowList {
                shadow.dataPublisher.sink { [weak self] _ in
                    self?._updateShadowData = true
                }.store(in: &shadowBufferSubscriptions)

                shadow.texturePublisher.sink { [weak self] _ in
                    self?._updateShadowTextures = true
                }.store(in: &shadowTextureSubscriptions)
            }

            _updateShadowData = true
            _updateShadowTextures = true
        }
    }

    private func updateShadowMatrices() {
        guard let shadowMatricesBuffer = shadowMatricesBuffer,
              _updateShadowMatrices else { return }

        shadowMatricesBuffer.update(data: shadowList.map { $0.camera.viewProjectionMatrix })

        _updateShadowMatrices = false
    }

    private func updateShadowData() {
        guard let shadowArgumentEncoder = shadowArgumentEncoder,
              let shadowDataBuffer = shadowDataBuffer,
              _updateShadowData else { return }

        shadowDataBuffer.update(data: shadowList.map { $0.data })
        shadowArgumentEncoder.setBuffer(
            shadowDataBuffer.buffer,
            offset: shadowDataBuffer.offset,
            index: FragmentBufferIndex.ShadowData.rawValue
        )

        _updateShadowData = false
    }

    private func updateShadowTextures() {
        guard let shadowArgumentEncoder = shadowArgumentEncoder,
              _updateShadowTextures else { return }

        for (index, shadow) in shadowList.enumerated() {
            shadowArgumentEncoder.setTexture(shadow.textures.first, index: FragmentTextureIndex.Shadow0.rawValue + index)
        }

        _updateShadowTextures = false
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
