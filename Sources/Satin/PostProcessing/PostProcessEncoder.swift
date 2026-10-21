//
//  PostProcessEncoder.swift
//  Satin
//
//  Created by Reza Ali on 4/16/20.
//

import Dispatch
import Foundation
import Metal
import simd

/// Draws one full-screen quad with its material: a post-processing pass. Its pass's load and store
/// settings live on `postProcessRenderer`.
open class PostProcessEncoder {
    public var label = "Post" {
        didSet {
            postProcessRenderer.label = label + " PostProcessRenderEncoder"
            mesh.label = label + " Mesh"
            scene.label = label + " Scene"
        }
    }

    /// Opt-in encoding queue. The producer captures a complete operation; render, compute and
    /// custom commands encode into one private buffer on this queue. Never target the producer.
    /// Queue every dependent encoder together. Commit earlier immediate work before switching.
    public var renderQueue: DispatchQueue?
    private let submissionAdmission: QueuedSubmission.Admission

    public let context: Context
    public let scene: Object
    public let mesh: Mesh
    public let camera: OrthographicCamera

    public let postProcessRenderer: PostProcessRenderEncoder

    public init(
        label: String = "Post Processor",
        context: Context,
        material: Material? = nil,
        colorPixelFormat: MTLPixelFormat? = nil,
        depthPixelFormat: MTLPixelFormat? = nil,
        stencilPixelFormat: MTLPixelFormat? = nil,
        clearColor: simd_float4 = .init(0, 0, 0, 1),
        colorLoadAction: MTLLoadAction = .clear,
        colorStoreAction: MTLStoreAction = .store,
        frameBufferOnly: Bool = true
    ) {
        self.label = label
        self.context = context
        submissionAdmission = QueuedSubmission.Admission(limit: context.maxBuffersInFlight)
        camera = OrthographicCamera(context: context)
        postProcessRenderer = PostProcessRenderEncoder(
            label: label + " PostProcessRenderEncoder",
            context: context,
            colorPixelFormat: colorPixelFormat ?? context.colorPixelFormat,
            depthPixelFormat: depthPixelFormat ?? context.depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat ?? context.stencilPixelFormat,
            clearColor: clearColor,
            colorLoadAction: colorLoadAction,
            colorStoreAction: colorStoreAction,
            frameBufferOnly: frameBufferOnly
        )

        if let material {
            precondition(
                material.context == context,
                "PostProcessEncoder material context (\(material.context.id)) must match processor context (\(context.id))"
            )
        }

        mesh = Mesh(context: context, label: label + "Mesh", geometry: QuadGeometry(context: context), material: material)
        scene = Object(context: context, label: label + " Scene", [mesh])
    }

    public final func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, renderTarget: MTLTexture) throws {
        try draw(frame: frame, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer,
                 viewports: [], renderTarget: renderTarget)
    }

    public final func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try draw(frame: frame, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer,
                 viewports: [])
    }

    public final func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = [], renderTarget: MTLTexture) throws {
        try draw(frame: frame, renderPassDescriptor: renderPassDescriptor.targeting(renderTarget, sampleCount: context.sampleCount),
                 commandBuffer: commandBuffer, viewports: viewports, viewMappings: viewMappings)
    }

    public final func draw(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping] = []) throws {
        RecordingProfile.noteFrame(frame.frameNumber)
        RecordingProfile.begin(.effects)
        defer { RecordingProfile.end() }
        let encodeQueue = renderQueue
        let encodingBuffer: MTLCommandBuffer
        if let encodeQueue {
            encodingBuffer = try QueuedSubmission.begin(commandBuffer: commandBuffer, renderQueue: encodeQueue, admission: submissionAdmission)
            encodingBuffer.label = label + " Queued Submission"
        } else {
            encodingBuffer = commandBuffer
        }
        do {
            let commands = encodeQueue == nil ? GPUCommandRecording(commandBuffer: encodingBuffer) : GPUCommandRecording(device: context.device)
            try encodeEffect(frame: frame, renderPassDescriptor: renderPassDescriptor, commands: commands,
                             viewports: viewports, viewMappings: viewMappings)
            if let encodeQueue {
                QueuedSubmission.schedule(commands.seal(), satinBuffer: encodingBuffer, renderQueue: encodeQueue, admission: submissionAdmission)
            }
        } catch {
            if encodeQueue != nil { QueuedSubmission.cancel(satinBuffer: encodingBuffer, admission: submissionAdmission) }
            throw error
        }
    }

    /// Prepare the whole effect on the producer. Child passes, compute and blits append to commands
    /// in order; captured Metal calls encode on the supplied queue. Never capture live self in replay.
    /// Keep private children's queues nil; calling super draws the quad without another admission.
    /// The descriptor contains the requested destination; compound effects use their output when absent.
    /// Empty viewports mean the configured default, resolved after preparation-time resize.
    open func encodeEffect(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor, commands: GPUCommandRecording,
                           viewports: [MTLViewport], viewMappings: [MTLVertexAmplificationViewMapping]) throws {
        let resolvedViewports = viewports.isEmpty ? [postProcessRenderer.viewport] : viewports
        try postProcessRenderer.record(frame: frame, renderPassDescriptor: renderPassDescriptor, commands: commands,
                                     mesh: mesh, cameras: Array(repeating: camera, count: max(1, max(context.vertexAmplificationCount, resolvedViewports.count))),
                                     viewports: resolvedViewports, viewMappings: viewMappings)
    }

    /// Explicit viewports describe the final destination. Intermediate passes scale their pixel
    /// coordinates; an empty list preserves each child's own viewport, resolved after preparation.
    func intermediateViewports(_ viewports: [MTLViewport], destination: MTLTexture?, target: MTLTexture) -> [MTLViewport] {
        let destination = destination ?? target
        let horizontalScale = Double(target.width) / Double(destination.width)
        let verticalScale = Double(target.height) / Double(destination.height)
        return viewports.map { viewport in
            MTLViewport(originX: viewport.originX * horizontalScale, originY: viewport.originY * verticalScale,
                        width: viewport.width * horizontalScale, height: viewport.height * verticalScale,
                        znear: viewport.znear, zfar: viewport.zfar)
        }
    }

    open func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        postProcessRenderer.resize(size)
    }
}
