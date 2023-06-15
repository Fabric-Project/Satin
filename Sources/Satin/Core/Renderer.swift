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
    public var preDraw: ((_ renderEncoder: MTLRenderCommandEncoder) -> Void)?
    public var postDraw: ((_ renderEncoder: MTLRenderCommandEncoder) -> Void)?

    public var sortObjects = false

    public var context: Context {
        didSet {
            if oldValue != context {
                updateColorTexture = true
                updateDepthTexture = true
                updateStencilTexture = true
            }
        }
    }

    public var size: (width: Float, height: Float) = (0, 0) {
        didSet {
            if oldValue.width != size.width || oldValue.height != size.height {
                updateViewport()

                updateColorTexture = true
                updateColorMultisampleTexture = true

                updateDepthTexture = true
                updateDepthMultisampleTexture = true

                updateStencilTexture = true
            }
        }
    }

    public var clearColor: MTLClearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
    public var clearDepth = 0.0
    public var clearStencil: UInt32 = 0

    private var updateColorTexture = true
    private var updateColorMultisampleTexture = true

    public private(set) var colorTexture: MTLTexture?
    public private(set) var colorMultisampleTexture: MTLTexture?

    public var colorLoadAction: MTLLoadAction = .clear
    public var colorStoreAction: MTLStoreAction = .store

    public var updateDepthTexture = true
    public var updateDepthMultisampleTexture = true

    public private(set) var depthTexture: MTLTexture?
    public private(set) var depthMultisampleTexture: MTLTexture?

    public var depthLoadAction: MTLLoadAction = .clear
    public var depthStoreAction: MTLStoreAction = .dontCare

    public var updateStencilTexture = true
    public var stencilTexture: MTLTexture?

    public var stencilLoadAction: MTLLoadAction = .clear
    public var stencilStoreAction: MTLStoreAction = .dontCare

    public var viewport = MTLViewport() {
        didSet {
            _viewport = simd_make_float4(
                Float(viewport.originX),
                Float(viewport.originY),
                Float(viewport.width),
                Float(viewport.height)
            )
        }
    }

    public var invertViewportNearFar = false {
        didSet {
            if invertViewportNearFar != oldValue {
                updateViewport()
            }
        }
    }

    private var _viewport: simd_float4 = .zero

    private var objectList = [Object]()
    private var renderList = [Renderable]()

    private var lightList = [Light]()
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

    // MARK: - Init

    public init(context: Context) {
        self.context = context
    }

    public func setClearColor(_ color: simd_float4) {
        clearColor = .init(red: Double(color.x), green: Double(color.y), blue: Double(color.z), alpha: Double(color.w))
    }

    // MARK: - Drawing

    public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, camera: Camera, renderTarget: MTLTexture)
    {
        if context.sampleCount > 1 {
            let resolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
            renderPassDescriptor.colorAttachments[0].resolveTexture = renderTarget
            draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, scene: scene, camera: camera)
            renderPassDescriptor.colorAttachments[0].resolveTexture = resolveTexture
        } else {
            let renderTexture = renderPassDescriptor.colorAttachments[0].texture
            renderPassDescriptor.colorAttachments[0].texture = renderTarget
            draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, scene: scene, camera: camera)
            renderPassDescriptor.colorAttachments[0].texture = renderTexture
        }
    }

    public func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, scene: Object, camera: Camera)
    {
        update(commandBuffer: commandBuffer, scene: scene, camera: camera)

        // render objects that cast shadows into the depth textures
        if !shadowCasters.isEmpty, !shadowReceivers.isEmpty {
            for light in lightList where light.castShadow {
                light.shadow.draw(commandBuffer: commandBuffer, renderables: shadowCasters)
            }
        }

        let inColorTexture = renderPassDescriptor.colorAttachments[0].texture
        let inColorResolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture

        let inDepthTexture = renderPassDescriptor.depthAttachment.texture
        let inDepthResolveTexture = renderPassDescriptor.depthAttachment.resolveTexture

        let inStencilTexture = renderPassDescriptor.stencilAttachment.texture

        defer {
            renderPassDescriptor.colorAttachments[0].texture = inColorTexture
            renderPassDescriptor.colorAttachments[0].resolveTexture = inColorResolveTexture

            renderPassDescriptor.depthAttachment.texture = inDepthTexture
            renderPassDescriptor.depthAttachment.resolveTexture = inDepthResolveTexture

            renderPassDescriptor.stencilAttachment.texture = inStencilTexture
        }

        if context.colorPixelFormat == .invalid {
            renderPassDescriptor.colorAttachments[0].texture = nil
            renderPassDescriptor.colorAttachments[0].resolveTexture = nil
        } else {
            if context.sampleCount > 1 {
                if inColorTexture?.sampleCount != context.sampleCount {
                    setupColorMultisampleTexture()
                    renderPassDescriptor.colorAttachments[0].texture = colorMultisampleTexture
                }

                if inColorResolveTexture == nil {
                    setupColorTexture()
                    renderPassDescriptor.colorAttachments[0].resolveTexture = colorTexture
                    renderPassDescriptor.renderTargetWidth = colorTexture!.width
                    renderPassDescriptor.renderTargetHeight = colorTexture!.height
                }

            } else if inColorTexture == nil {
                setupColorTexture()
                renderPassDescriptor.colorAttachments[0].texture = colorTexture
                renderPassDescriptor.renderTargetWidth = colorTexture!.width
                renderPassDescriptor.renderTargetHeight = colorTexture!.height
            }
        }

        if context.depthPixelFormat == .invalid {
            renderPassDescriptor.depthAttachment.texture = nil
        } else {
            if context.sampleCount > 1 {
                if inDepthTexture?.sampleCount != context.sampleCount {
                    setupDepthMultisampleTexture()
                    renderPassDescriptor.depthAttachment.texture = depthMultisampleTexture
                }

                if inDepthResolveTexture == nil {
                    setupDepthTexture()
                    renderPassDescriptor.depthAttachment.resolveTexture = depthTexture
                }

            } else if inDepthTexture == nil {
                setupDepthTexture()
                renderPassDescriptor.depthAttachment.texture = depthTexture
            }

            if context.depthPixelFormat == .depth32Float_stencil8 {
                renderPassDescriptor.stencilAttachment.texture = depthTexture
            }
        }

        if context.stencilPixelFormat == .invalid {
            renderPassDescriptor.stencilAttachment.texture = nil
        } else if inStencilTexture == nil ||
            inStencilTexture?.sampleCount != context.sampleCount ||
            inStencilTexture?.pixelFormat != context.stencilPixelFormat
        {
            setupStencilTexture()
            if context.depthPixelFormat == .depth32Float_stencil8 {
                renderPassDescriptor.stencilAttachment.texture = depthTexture
            } else {
                renderPassDescriptor.stencilAttachment.texture = stencilTexture
            }
        }

        if context.sampleCount > 1 {
            if colorStoreAction == .store || colorStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.colorAttachments[0].storeAction = .storeAndMultisampleResolve
            } else {
                renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
            }
        } else {
            if colorStoreAction == .store || colorStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.colorAttachments[0].storeAction = .store
            } else {
                renderPassDescriptor.colorAttachments[0].storeAction = .dontCare
            }
        }

        if context.sampleCount > 1 {
            if depthStoreAction == .store || depthStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.depthAttachment.storeAction = .storeAndMultisampleResolve
            } else {
                renderPassDescriptor.depthAttachment.storeAction = .multisampleResolve
            }
        } else {
            if depthStoreAction == .store || depthStoreAction == .storeAndMultisampleResolve {
                renderPassDescriptor.depthAttachment.storeAction = .store
            } else {
                renderPassDescriptor.depthAttachment.storeAction = .dontCare
            }
        }

        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.colorAttachments[0].loadAction = colorLoadAction

        renderPassDescriptor.depthAttachment.loadAction = depthLoadAction
        renderPassDescriptor.depthAttachment.clearDepth = clearDepth

        renderPassDescriptor.stencilAttachment.loadAction = stencilLoadAction
        renderPassDescriptor.stencilAttachment.storeAction = stencilStoreAction
        renderPassDescriptor.stencilAttachment.clearStencil = clearStencil

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderEncoder.label = label + " Encoder"
            renderEncoder.setViewport(viewport)
            encode(renderEncoder: renderEncoder, scene: scene, camera: camera)
            renderEncoder.endEncoding()
        }
    }

    // MARK: - Internal Update

    private func update(commandBuffer: MTLCommandBuffer, scene: Object, camera: Camera) {
        onUpdate?()

        objectList.removeAll(keepingCapacity: true)
        renderList.removeAll(keepingCapacity: true)
        lightList.removeAll(keepingCapacity: true)

        shadowList.removeAll(keepingCapacity: true)
        shadowCasters.removeAll(keepingCapacity: true)
        shadowReceivers.removeAll(keepingCapacity: true)

        camera.update(commandBuffer) // FIXME: - traverse children and make sure you update everything

        updateLists(object: scene)

        updateScene(commandBuffer: commandBuffer, camera: camera)
        updateLights()
        updateShadows()
    }

    private func updateLists(object: Object, visible: Bool = true) {
        objectList.append(object)

        let isVisible = visible && object.visible
        if isVisible {
            if let light = object as? Light {
                lightList.append(light)
                if light.castShadow {
                    shadowList.append(light.shadow)
                }
            }
            if let renderable = object as? Renderable {
                renderList.append(renderable)
                if renderable.receiveShadow {
                    shadowReceivers.append(renderable)
                }
                if renderable.castShadow {
                    shadowCasters.append(renderable)
                }
            }
        }

        for child in object.children {
            updateLists(object: child, visible: isVisible)
        }
    }

    private func updateScene(commandBuffer: MTLCommandBuffer, camera: Camera) {
        let lightCount = lightList.count
        let shadowCount = shadowList.count

        var environmentIntensity: Float = 1.0
        var cubemapTexture: MTLTexture? = nil
        var reflectionTexture: MTLTexture? = nil
        var irradianceTexture: MTLTexture? = nil
        var brdfTexture: MTLTexture? = nil
        var reflectionTexcoordTransform = matrix_identity_float3x3
        var irradianceTexcoordTransform = matrix_identity_float3x3

        for object in objectList {
            if let environment = object as? Environment {
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
                    }

                    if renderable.receiveShadow {
                        material.shadowCount = shadowCount
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

                    if let cubemapTexture = cubemapTexture,
                        let skyboxMaterial = material as? SkyboxMaterial {
                        skyboxMaterial.texture = cubemapTexture
                        skyboxMaterial.texcoordTransform = reflectionTexcoordTransform
                        skyboxMaterial.environmentIntensity = environmentIntensity
                    }
                }
            } else {
                object.update(camera: camera, viewport: _viewport)
            }

            object.context = context
            object.update(commandBuffer)
        }
    }

    // MARK: - Internal Encoding

    private func encode(renderEncoder: MTLRenderCommandEncoder, scene: Object, camera: Camera) {
        renderEncoder.pushDebugGroup(label + " Pass")
        preDraw?(renderEncoder)

        let renderables = sortObjects ? renderList.sorted { $0.renderOrder < $1.renderOrder } : renderList

        if !renderables.isEmpty {
            for shadow in shadowList {
                if let shadowTexture = shadow.texture {
                    renderEncoder.useResource(shadowTexture, usage: .read, stages: .fragment)
                }
            }

            if let shadowDataBuffer = shadowDataBuffer {
                renderEncoder.useResource(shadowDataBuffer.buffer, usage: .read, stages: .fragment)
            }

            for var renderable in renderables where renderable.drawable {
                _encode(renderEncoder: renderEncoder, renderable: &renderable, camera: camera)
            }
        }

        postDraw?(renderEncoder)
        renderEncoder.popDebugGroup()
    }

    private func _encode(renderEncoder: MTLRenderCommandEncoder, renderable: inout Renderable, camera: Camera) {
        renderEncoder.pushDebugGroup(renderable.label)

        let materials = renderable.materials
        let lighting = materials.filter { $0.lighting }
        let receiveShadow = materials.filter { $0.receiveShadow }

        if !lighting.isEmpty, let lightBuffer = lightDataBuffer {
            renderEncoder.setFragmentBuffer(
                lightBuffer.buffer,
                offset: lightBuffer.offset,
                index: FragmentBufferIndex.Lighting.rawValue
            )
        }

        if !receiveShadow.isEmpty {
            if let shadowBuffer = shadowMatricesBuffer {
                renderEncoder.setVertexBuffer(
                    shadowBuffer.buffer,
                    offset: shadowBuffer.offset,
                    index: VertexBufferIndex.ShadowMatrices.rawValue
                )
            }

            if let shadowArgumentBuffer = shadowArgumentBuffer {
                renderEncoder.setFragmentBuffer(
                    shadowArgumentBuffer,
                    offset: 0,
                    index: FragmentBufferIndex.Shadows.rawValue
                )
            }
        }

        renderable.update(camera: camera, viewport: _viewport)

        if renderable.cullMode == .none, renderable.opaque == false {

            renderable.cullMode = .front
            renderable.draw(renderEncoder: renderEncoder, shadow: false)

            renderable.cullMode = .back
            renderable.draw(renderEncoder: renderEncoder, shadow: false)

            renderable.cullMode = .none
        }
        else {
            renderable.draw(renderEncoder: renderEncoder, shadow: false)
        }

        renderEncoder.popDebugGroup()
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

    // MARK: - Textures

    private func setupColorMultisampleTexture() {
        guard updateColorMultisampleTexture,
              context.colorPixelFormat != .invalid,
              context.sampleCount > 1,
              size.width > 1,
              size.height > 1
        else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: context.colorPixelFormat,
                width: Int(size.width),
                height: Int(size.height),
                mipmapped: false
            )
        descriptor.sampleCount = context.sampleCount
        descriptor.textureType = .type2DMultisample
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate

        colorMultisampleTexture = context.device.makeTexture(descriptor: descriptor)
        colorMultisampleTexture?.label = label + "Multisample Color Texture"

        updateColorMultisampleTexture = false
    }

    private func setupColorTexture() {
        guard updateColorTexture, context.colorPixelFormat != .invalid, size.width > 1, size.height > 1 else { return }

        let descriptor = MTLTextureDescriptor
            .texture2DDescriptor(
                pixelFormat: context.colorPixelFormat,
                width: Int(size.width),
                height: Int(size.height),
                mipmapped: false
            )
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate

        colorTexture = context.device.makeTexture(descriptor: descriptor)
        colorTexture?.label = label + " Color Texture"

        updateColorTexture = false
    }

    private func setupDepthMultisampleTexture() {
        guard updateDepthMultisampleTexture,
              context.depthPixelFormat != .invalid,
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
        descriptor.textureType = .type2DMultisample
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate

        depthMultisampleTexture = context.device.makeTexture(descriptor: descriptor)
        depthMultisampleTexture?.label = label + "Multisample Depth Texture"

        updateDepthMultisampleTexture = false
    }

    private func setupDepthTexture() {
        guard updateDepthTexture,
              context.depthPixelFormat != .invalid,
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
        descriptor.textureType = .type2D
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate

        depthTexture = context.device.makeTexture(descriptor: descriptor)
        depthTexture?.label = label + " Depth Texture"

        updateDepthTexture = false
    }

    private func setupStencilTexture() {
        guard updateStencilTexture, context.stencilPixelFormat != .invalid, size.width > 1, size.height > 1 else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = context.stencilPixelFormat
        descriptor.width = Int(size.width)
        descriptor.height = Int(size.height)
        descriptor.sampleCount = context.sampleCount
        descriptor.textureType = context.sampleCount > 1 ? .type2DMultisample : .type2D
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate

        stencilTexture = context.device.makeTexture(descriptor: descriptor)
        stencilTexture?.label = label + " Stencil Texture"

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
            lightDataBuffer = StructBuffer<LightData>.init(
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
            shadowMatricesBuffer = StructBuffer<simd_float4x4>.init(
                device: context.device,
                count: shadowList.count,
                label: "Shadow Matrices Buffer"
            )

            for light in lightList where light.castShadow {
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

                let shadowDataBuffer = StructBuffer<ShadowData>.init(
                    device: context.device,
                    count: shadowList.count,
                    label: "Shadow Data Buffer"
                )

                self.shadowArgumentBuffer = shadowArgumentBuffer
                self.shadowArgumentEncoder = shadowArgumentEncoder
                self.shadowDataBuffer = shadowDataBuffer

                shadowArgumentEncoder.setBuffer(shadowDataBuffer.buffer, offset: shadowDataBuffer.offset, index: FragmentBufferIndex.ShadowData.rawValue)

                for (index, shadow) in shadowList.enumerated() {
                    shadowArgumentEncoder.setTexture(shadow.texture, index: FragmentTextureIndex.Shadow0.rawValue + index)
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
            shadowArgumentEncoder.setTexture(shadow.texture, index: FragmentTextureIndex.Shadow0.rawValue + index)
        }

        _updateShadowTextures = false
    }

    // MARK: - Compile

    // MARK: - Internal Update

    public func compile(scene: Object, camera: Camera) {
        guard let commandQueue = context.device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        update(commandBuffer: commandBuffer, scene: scene, camera: camera)
        commandBuffer.commit()
    }
}
