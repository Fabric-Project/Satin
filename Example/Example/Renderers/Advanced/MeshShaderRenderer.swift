//
//  MeshShaderRenderer.swift
//  Example
//
//  Created by Reza Ali on 3/17/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import Satin

final class MeshShaderRenderer: BaseRenderer {
    lazy var geometry = IcoSphereGeometry(context: defaultContext, radius: 1.0, resolution: 4)
    lazy var mesh: Mesh = {
        let material = BasicDiffuseMaterial(context: defaultContext, hardness: 0.7)
        material.ambient = 0.15
        return Mesh(context: defaultContext, geometry: geometry, material: material)
    }()
    fileprivate lazy var meshNormals = CustomMesh(context: defaultContext, geometry: geometry, material: CustomMaterial(context: defaultContext, pipelinesURL: pipelinesURL))

    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])

    lazy var camera = PerspectiveCamera(context: defaultContext, position: .init(0.0, 0.0, 8.0), near: 0.01, far: 100.0, fov: 45)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    override func setup() throws {
        mesh.triangleFillMode = MTLTriangleFillMode.lines
        mesh.add(meshNormals)
#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    override func update(frame: FrameTime) throws {
        try super.update(frame: frame)

        meshNormals.material?.set("Time", Float(frame.time))
        cameraController.update(frame: frame)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try renderer.draw(
            frame: frameTime,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}

private final class CustomShader: SourceShader {
    public var objectFunctionName = "shaderObject"
    public var meshFunctionName = "shaderMesh"

    var meshFunction: String?

    convenience init(_ context: Context,
                     _ label: String,
                     _ pipelineURL: URL,
                     _ objectFunctionName: String? = nil,
                     _ meshFunctionName: String? = nil,
                     _: String? = nil)
    {
        self.init(context: context, label: label, pipelineURL: pipelineURL)
        self.objectFunctionName = objectFunctionName ?? label.camelCase + "Object"
        self.meshFunctionName = meshFunctionName ?? label.camelCase + "Mesh"
    }

    required init(configuration: ShaderConfiguration) {
        super.init(configuration: configuration)
    }

    override public func makePipeline() throws -> (pipeline: MTLRenderPipelineState?, reflection: MTLRenderPipelineReflection?) {
        if #available(macOS 13.0, iOS 16.0, *) {
            let context = context
            if let library = try ShaderLibraryCache.getLibrary(configuration: configuration.getLibraryConfiguration(), device: context.device),
               let objectFunction = library.makeFunction(name: objectFunctionName),
               let meshFunction = library.makeFunction(name: meshFunctionName),
               let fragmentFunction = library.makeFunction(name: fragmentFunctionName)
            {
                var descriptor = MTLMeshRenderPipelineDescriptor()
                descriptor.label = label + " Mesh"

                descriptor.objectFunction = objectFunction
                descriptor.meshFunction = meshFunction
                descriptor.fragmentFunction = fragmentFunction

                descriptor.rasterSampleCount = context.sampleCount
                descriptor.colorAttachments[0].pixelFormat = context.colorPixelFormat
                descriptor.depthAttachmentPixelFormat = context.depthPixelFormat
                descriptor.stencilAttachmentPixelFormat = context.stencilPixelFormat

                setupMeshPipelineDescriptorBlending(blending: configuration.blending, descriptor: &descriptor)
                return try context.device.makeRenderPipelineState(descriptor: descriptor, options: [.bindingInfo, .bufferTypeInfo])
            } else {
                return (nil, nil)
            }
        } else {
            fatalError("Mesh Shader's are not supported")
        }
    }

    @available(macOS 13.0, iOS 16.0, *)
    public func setupMeshPipelineDescriptorBlending(blending: ShaderBlending, descriptor: inout MTLMeshRenderPipelineDescriptor) {
        guard blending.type != .disabled, let colorAttachment = descriptor.colorAttachments[0] else { return }

        colorAttachment.isBlendingEnabled = true

        switch blending.type {
            case .alpha:
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .add
                colorAttachment.alphaBlendOperation = .add
            case .additive:
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .one
                colorAttachment.destinationRGBBlendFactor = .one
                colorAttachment.destinationAlphaBlendFactor = .one
                colorAttachment.rgbBlendOperation = .add
                colorAttachment.alphaBlendOperation = .add
            case .subtract:
                colorAttachment.sourceRGBBlendFactor = .sourceAlpha
                colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
                colorAttachment.destinationRGBBlendFactor = .oneMinusBlendColor
                colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                colorAttachment.rgbBlendOperation = .reverseSubtract
                colorAttachment.alphaBlendOperation = .add
            case .custom:
                colorAttachment.sourceRGBBlendFactor = blending.sourceRGBBlendFactor
                colorAttachment.sourceAlphaBlendFactor = blending.sourceAlphaBlendFactor
                colorAttachment.destinationRGBBlendFactor = blending.destinationRGBBlendFactor
                colorAttachment.destinationAlphaBlendFactor = blending.destinationAlphaBlendFactor
                colorAttachment.rgbBlendOperation = blending.rgbBlendOperation
                colorAttachment.alphaBlendOperation = blending.alphaBlendOperation
            default:
                break
        }
    }
}

private final class CustomMaterial: SourceMaterial {
    init(context: Context, pipelinesURL: URL) {
        super.init(context: context, pipelinesURL: pipelinesURL)
//        set("Time", 0.0)
    }

    required init(context: Context) {
        super.init(context: context)
    }

    required init(from _: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    override func createShader() -> Shader {
        let shader = CustomShader(context, label, pipelineURL)
        shader.live = true
        return shader
    }

    override func draw(in context: MaterialDrawContext) throws {
        try super.draw(in: context)
        guard #available(macOS 13.0, iOS 16.0, *), let uniforms = try uniformsBinding(in: context) else { return }

        // The mesh pipeline reads material uniforms in its object and mesh stages too.
        context.setObjectBuffer(uniforms.buffer, offset: uniforms.offset, index: .MaterialUniforms)
        context.setMeshBuffer(uniforms.buffer, offset: uniforms.offset, index: .MaterialUniforms)
        if !context.isShadowPass {
            try context.setFragmentBuffer(uniforms.buffer, offset: uniforms.offset, index: .MaterialUniforms)
        }
    }
}

private final class CustomMesh: Mesh {

    public required init(from _: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    init(context: Context, geometry: Geometry, material: Material?) {
        super.init(context: context, label: "Custom Mesh", geometry: geometry, material: material)
    }

    // MARK: - Draw

    override func draw(in context: RenderableDrawContext) throws {
        guard #available(macOS 13.0, iOS 16.0, *),
              let material,
              let vertexBuffer = geometry.vertexBuffers[VertexBufferIndex.Vertices]
        else { return }

        try material.draw(in: context.materialContext(layout: nil))

        // A mesh-shader dispatch, recorded as data like any other draw.
        context.setObjectBuffer(vertexBuffer, index: .Vertices)
        if let indexBuffer = geometry.indexBuffer {
            context.setObjectBuffer(indexBuffer, index: .Indicies)
        }
        context.setMeshBuffer(context.vertexUniforms.buffer, offset: context.vertexUniforms.offset, index: .VertexUniforms)
        context.drawMeshThreadgroups(
            MTLSizeMake(geometry.indexCount / 3, 1, 1),
            threadsPerObjectThreadgroup: MTLSizeMake(1, 1, 1),
            threadsPerMeshThreadgroup: MTLSizeMake(36, 1, 1)
        )
    }
}
