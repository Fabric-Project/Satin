//
//  Renderable.swift
//
//
//  Created by Reza Ali on 4/19/22.
//

import Combine
import Metal
import simd

open class Renderable : Object {
    enum MaterialPass {
        case all
        case opaque
        case alphaTransparent
        case classicTransparent
        case surfaceOpaque
        case unlitOpaque
    }

    open var opaque: Bool { material!.blending == .disabled }
    
    final let doubleSidedPublisher = PassthroughSubject<Bool, Never>()
    open var doubleSided: Bool = false {
        didSet {
            doubleSidedPublisher.send(doubleSided)
        }
    }

    final let renderOrderPublisher = PassthroughSubject<Int, Never>()
    open var renderOrder = 0 {
        didSet {
            renderOrderPublisher.send(renderOrder)
        }
    }

    final let renderLayerPublisher = PassthroughSubject<RenderLayer, Never>()
    open var renderLayer: RenderLayer = .opaque {
        didSet {
            renderLayerPublisher.send(renderLayer)
        }
    }
    
    open var lighting: Bool { material?.lighting ?? false }


    final let receiveShadowPublisher = PassthroughSubject<Bool, Never>()
    open var receiveShadow = false {
        didSet {
            receiveShadowPublisher.send(receiveShadow)
        }
    }

    final let castShadowPublisher = PassthroughSubject<Bool, Never>()
    open var castShadow = false {
        didSet {
            castShadowPublisher.send(castShadow)
        }
    }


    final let cullModePublisher = PassthroughSubject<MTLCullMode, Never>()
    open var cullMode: MTLCullMode = .back {
        didSet {
            cullModePublisher.send(cullMode)
        }
    }

    open var windingOrder: MTLWinding = .counterClockwise
    
    final let triangleFillModePublisher = PassthroughSubject<MTLTriangleFillMode, Never>()
    open var triangleFillMode: MTLTriangleFillMode = .fill {
        didSet {
            triangleFillModePublisher.send(triangleFillMode)
        }
    }
    
    // MARK: - Occurrences and Motion

    /// What one occurrence of this renderable draws with: its model and normal matrices, and the
    /// model matrix the same occurrence had last frame, for motion. Every pass of the occurrence
    /// (shadow lights, faces, colour) reads it; only the engine advances it.
    struct Occurrence {
        var modelMatrix: simd_float4x4
        var normalMatrix: simd_float3x3
        var previousModelMatrix: simd_float4x4
    }

    private(set) var occurrence = Occurrence(
        modelMatrix: matrix_identity_float4x4,
        normalMatrix: matrix_identity_float3x3,
        previousModelMatrix: matrix_identity_float4x4
    )

    /// Model matrices by draw ordinal: the kth occurrence of this frame pairs with the kth of the
    /// last frame this renderable was drawn in, if that was the frame before.
    private var previousFrameModelMatrices: [simd_float4x4] = []
    private var currentFrameModelMatrices: [simd_float4x4] = []
    private var motionFrameNumber: Int?

    /// Starts an occurrence of this renderable in `frame`, before any of its passes record. The
    /// first occurrence of a frame moves the last frame's samples into place; an ordinal with no
    /// sample from the frame before starts with no motion.
    func beginOccurrence(frame: FrameTime) {
        if motionFrameNumber != frame.frameNumber {
            if let motionFrameNumber, motionFrameNumber == frame.frameNumber - 1 {
                swap(&previousFrameModelMatrices, &currentFrameModelMatrices)
            } else {
                previousFrameModelMatrices.removeAll(keepingCapacity: true)
            }
            currentFrameModelMatrices.removeAll(keepingCapacity: true)
            motionFrameNumber = frame.frameNumber
        }

        let modelMatrix = selectedRepeatedSourceState?.modelMatrix ?? worldMatrix
        let ordinal = currentFrameModelMatrices.count
        let previousModelMatrix = ordinal < previousFrameModelMatrices.count ? previousFrameModelMatrices[ordinal] : modelMatrix
        currentFrameModelMatrices.append(modelMatrix)

        occurrence = Occurrence(
            modelMatrix: modelMatrix,
            normalMatrix: selectedRepeatedSourceState?.normalMatrix ?? normalMatrix,
            previousModelMatrix: previousModelMatrix
        )
    }

    /// Forgets this renderable's motion: its next occurrences draw with none. For an owner whose
    /// drawing changed in a way ordinals can't see, such as a reordered or resized set of draws.
    public func resetMotion() {
        previousFrameModelMatrices.removeAll(keepingCapacity: true)
        currentFrameModelMatrices.removeAll(keepingCapacity: true)
    }

    // MARK: - Repeated Encoding State

    /// The world and normal matrices one repetition drew with.
    struct RepeatedSourceState {
        let modelMatrix: simd_float4x4
        let normalMatrix: simd_float3x3
    }

    private var repeatedSourceStates: [RepeatedSourceState] = []
    private var selectedRepeatedSourceState: RepeatedSourceState?

    open var material: Material? = nil
    open var materials: [Material] = []

    open var preDraw: ((_ renderEncoder: MTLRenderCommandEncoder) -> Void)? = nil

    /// Records this renderable's draw for one render event: its bindings, material and geometry
    /// draws, and any custom commands. Recorded values are captured, so later changes don't affect
    /// this draw. Recording no draw call means it doesn't draw in this pass.
    open func draw(in context: RenderableDrawContext) {
        fatalError("Subclasses must implement this method")
    }

    // TODO(render-packets): Repeated encoding is a stopgap. Every resource (vertex and material
    // uniforms, instance matrices, joint palettes, geometry draw states) rotates its own slots, and
    // each assumes the caller's order: per repetition, update then capture; then draw everything.
    // Replace it with an engine-style render packet: per frame and per repetition, prepare a packet
    // holding exactly what one draw needs (pipeline, uniforms, instance and joint matrices with
    // their previous values, buffers and offsets), then submit packets. Frame identity, per-draw
    // motion history and in-flight safety then live in one place instead of in every resource.
    /// Prepares this renderable to be encoded `count` times in a single render pass.
    /// Expands all ring buffers (vertex uniforms, material uniforms, geometry) so that
    /// each encoding sees independent data. Call once before the iteration loop begins,
    /// whenever `count` or the set of child renderables changes.
    open func prepareForRepeatedEncoding(count: Int) {
        let count = max(1, count)
        if count > 1 {
            repeatedSourceStates.reserveCapacity(count)
        } else {
            repeatedSourceStates.removeAll(keepingCapacity: true)
            selectedRepeatedSourceState = nil
        }
    }

    open func captureRepeatedEncodingState(iteration: Int, count: Int) {
        let count = max(1, count)
        guard count > 1 else {
            repeatedSourceStates.removeAll(keepingCapacity: true)
            selectedRepeatedSourceState = nil
            return
        }

        let state = RepeatedSourceState(modelMatrix: worldMatrix, normalMatrix: normalMatrix)
        if repeatedSourceStates.count != count {
            repeatedSourceStates = Array(repeating: state, count: count)
        }
        repeatedSourceStates[min(max(iteration, 0), count - 1)] = state
    }

    open func selectRepeatedEncodingState(iteration: Int, count: Int) {
        let count = max(1, count)
        guard count > 1, repeatedSourceStates.count == count else {
            selectedRepeatedSourceState = nil
            return
        }
        selectedRepeatedSourceState = repeatedSourceStates[min(max(iteration, 0), count - 1)]
    }

    open func captureRepeatedEncodingSlot(iteration: Int, count: Int) {
        captureRepeatedEncodingState(iteration: iteration, count: count)
    }

    open func selectRepeatedEncodingSlot(iteration: Int, count: Int) {
        selectRepeatedEncodingState(iteration: iteration, count: count)
    }
}
