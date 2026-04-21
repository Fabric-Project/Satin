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

    public var outputs: RendererOutputs = []

    // Each output prepass needs its own Context so the pipeline compiles for the correct pixel format.
    // normalPassContext uses rgba16Float: world-space normals are signed unit vectors.
    private lazy var normalPassContext = Context(
        device: context.device,
        sampleCount: 1,
        colorPixelFormat: .rgba16Float,
        depthPixelFormat: context.depthPixelFormat
    )
    // velocityPassContext uses rg16Float: velocity is a signed NDC displacement (can be < 0 or > 1).
    private lazy var velocityPassContext = Context(
        device: context.device,
        sampleCount: 1,
        colorPixelFormat: .rg16Float,
        depthPixelFormat: context.depthPixelFormat
    )

    private lazy var normalColorMaterial = NormalColorMaterial(context: normalPassContext)
    private lazy var velocityMaterial = VelocityMaterial(context: velocityPassContext)

    private var updateNormalTexture = true
    public private(set) var normalTexture: MTLTexture?
    public var normalTextureStorageMode: MTLStorageMode = .private {
        didSet {
            if oldValue != normalTextureStorageMode { updateNormalTexture = true }
        }
    }

    private var updateVelocityTexture = true
    public private(set) var velocityTexture: MTLTexture?
    public var velocityTextureStorageMode: MTLStorageMode = .private {
        didSet {
            if oldValue != velocityTextureStorageMode { updateVelocityTexture = true }
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

        if outputs.contains(.normals) {
            setupNormalTexture()
        }
        if outputs.contains(.velocity) {
            setupVelocityTexture()
        }

        if renderLists.isEmpty {
            if colorLoadAction == .clear, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
#if DEBUG
                renderEncoder.pushDebugGroup(label + " Empty Pass")
#endif
                renderEncoder.setViewports(viewports)
#if DEBUG
                renderEncoder.popDebugGroup()
#endif
                renderEncoder.endEncoding()
            }
        } else {
            let renderPassLists = renderLists.sorted { $0.key < $1.key }

            for (pass, renderPassList) in renderPassLists.enumerated() {
                let renderList = renderPassList.value
                let renderables = renderList.getRenderables(sorted: sortObjects)

                if !renderables.isEmpty, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.label = label + " Pass \(pass)"
#if DEBUG
                    renderEncoder.pushDebugGroup("Pass \(pass)")
#endif
                    renderEncoder.setViewports(viewports)

                    if context.vertexAmplificationCount > 1 {
                        var maps = viewMappings
                        if maps.isEmpty {
                            maps = (0..<context.vertexAmplificationCount).map { .init(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0)) }
                        }
                        renderEncoder.setVertexAmplificationCount(context.vertexAmplificationCount, viewMappings: &maps)
                    }

                    encode(
                        renderEncoder: renderEncoder,
                        pass: pass,
                        renderables: renderables,
                        cameras: cameras,
                        viewports: simd_viewports
                    )

#if DEBUG
                    renderEncoder.popDebugGroup()
#endif
                    renderEncoder.endEncoding()

                    // Not sure why this is necessary?
//                    renderPassDescriptor.colorAttachments[0].loadAction = .load
//                    renderPassDescriptor.depthAttachment.loadAction = .load
//                    renderPassDescriptor.stencilAttachment.loadAction = .load
                }
            }
        }

        if !outputs.isEmpty, let primaryCamera = cameras.first {
            // Prefer the resolved (single-sample) depth so prepasses that run at sampleCount=1
            // don't receive an MSAA multisample texture as their depth attachment.
            let renderedDepthTexture = renderPassDescriptor.depthAttachment.resolveTexture
                ?? renderPassDescriptor.depthAttachment.texture
                ?? depthTexture
            if outputs.contains(.normals) {
                encodeNormalPrepass(commandBuffer: commandBuffer, scene: scene, camera: primaryCamera, viewports: viewports, renderedDepthTexture: renderedDepthTexture)
            }
            if outputs.contains(.velocity) {
                encodeVelocityPrepass(commandBuffer: commandBuffer, scene: scene, camera: primaryCamera, viewports: viewports, renderedDepthTexture: renderedDepthTexture)
            }
        }
    }

    private func encodeNormalPrepass(
        commandBuffer: MTLCommandBuffer,
        scene: Object,
        camera: Camera,
        viewports: [MTLViewport],
        renderedDepthTexture: MTLTexture? = nil
    ) {
        guard let normalTexture else { return }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = normalTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        let depthSource = renderedDepthTexture ?? depthTexture
        if let depthSource {
            rpd.depthAttachment.texture = depthSource
            rpd.depthAttachment.loadAction = .load
            rpd.depthAttachment.storeAction = .dontCare
        }

        let simd_viewports = viewports.map(\.float4)
        let renderPassLists = renderLists.sorted { $0.key < $1.key }
        for (pass, renderPassList) in renderPassLists.enumerated() {
            let renderables = renderPassList.value.getRenderables(sorted: false)
            if !renderables.isEmpty, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
                renderEncoder.label = label + " Normal Prepass"
                renderEncoder.setViewports(viewports)
                encode(
                    renderEncoder: renderEncoder,
                    pass: pass,
                    renderables: renderables,
                    cameras: [camera],
                    viewports: simd_viewports,
                    overrideMaterial: normalColorMaterial
                )
                renderEncoder.endEncoding()
            }
        }
    }

    private func encodeVelocityPrepass(
        commandBuffer: MTLCommandBuffer,
        scene: Object,
        camera: Camera,
        viewports: [MTLViewport],
        renderedDepthTexture: MTLTexture? = nil
    ) {
        guard let velocityTexture else { return }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = velocityTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let depthSource = renderedDepthTexture ?? depthTexture
        if let depthSource {
            rpd.depthAttachment.texture = depthSource
            rpd.depthAttachment.loadAction = .load
            rpd.depthAttachment.storeAction = .dontCare
        }

        let simd_viewports = viewports.map(\.float4)
        let renderPassLists = renderLists.sorted { $0.key < $1.key }
        for (pass, renderPassList) in renderPassLists.enumerated() {
            let renderables = renderPassList.value.getRenderables(sorted: false)
            if !renderables.isEmpty, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
                renderEncoder.label = label + " Velocity Prepass"
                renderEncoder.setViewports(viewports)
                encode(
                    renderEncoder: renderEncoder,
                    pass: pass,
                    renderables: renderables,
                    cameras: [camera],
                    viewports: simd_viewports,
                    overrideMaterial: velocityMaterial
                )
                renderEncoder.endEncoding()
            }
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

        var environmentIntensity: Float = 1.0
        var cubemapTexture: MTLTexture?
        var reflectionTexture: MTLTexture?
        var irradianceTexture: MTLTexture?
        var brdfTexture: MTLTexture?
        var reflectionTexcoordTransform = matrix_identity_float3x3
        var irradianceTexcoordTransform = matrix_identity_float3x3

        for object in objectList {
            if let environment = object as? IBLEnvironment {
                environmentIntensity = environment.environmentIntensity
                cubemapTexture = environment.cubemapTexture

                reflectionTexture = environment.reflectionTexture
                reflectionTexcoordTransform = environment.reflectionTexcoordTransform

                irradianceTexture = environment.irradianceTexture
                irradianceTexcoordTransform = environment.irradianceTexcoordTransform

                brdfTexture = environment.brdfTexture
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
                        pbrMaterial.environmentIntensity = environmentIntensity
                        if let reflectionTexture = reflectionTexture {
                            pbrMaterial.setTexture(reflectionTexture, type: .reflection)
                            pbrMaterial.setTexcoordTransform(reflectionTexcoordTransform, type: .reflection)
                        }
                        if let irradianceTexture = irradianceTexture {
                            pbrMaterial.setTexture(irradianceTexture, type: .irradiance)
                            pbrMaterial.setTexcoordTransform(irradianceTexcoordTransform, type: .irradiance)
                        }
                        if let brdfTexture = brdfTexture {
                            pbrMaterial.setTexture(brdfTexture, type: .brdf)
                        }
                    }

                    if let cubemapTexture = cubemapTexture, let skyboxMaterial = material as? SkyboxMaterial {
                        skyboxMaterial.texture = cubemapTexture
                        skyboxMaterial.texcoordTransform = simd_float4x4(textureTransform: reflectionTexcoordTransform)
                        skyboxMaterial.environmentIntensity = environmentIntensity
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
        cameras: [Camera],
        viewports: [simd_float4],
        overrideMaterial: Material? = nil
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

        for renderable in renderables where renderable.isDrawable(renderContext: context, shadow: false) {
            _encode(
                renderEncoder: renderEncoder,
                renderEncoderState: renderEncoderState,
                renderable: renderable,
                cameras: cameras,
                viewports: viewports,
                overrideMaterial: overrideMaterial
            )
        }
    }

    private func _encode(renderEncoder: MTLRenderCommandEncoder, renderEncoderState: RenderEncoderState, renderable: Renderable, cameras: [Camera], viewports: [simd_float4], overrideMaterial: Material? = nil) {
#if DEBUG
        renderEncoder.pushDebugGroup(renderable.label)
#endif
        let savedMaterial = renderable.material
        // Determine which context to use for pipeline/uniform lookups
        let renderContext = overrideMaterial?.context ?? context

        if let overrideMaterial {
            renderable.material = overrideMaterial
            // Lazily create a vertex uniform buffer for the prepass context if not yet present
            if renderable.vertexUniforms[renderContext] == nil {
                renderable.vertexUniforms[renderContext] = VertexUniformBuffer(context: renderContext)
            }
        }
        defer { if overrideMaterial != nil { renderable.material = savedMaterial } }

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

    private func setupNormalTexture() {
        guard updateNormalTexture, size.width > 1, size.height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
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

    private func setupVelocityTexture() {
        guard updateVelocityTexture, size.width > 1, size.height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float,
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

}
