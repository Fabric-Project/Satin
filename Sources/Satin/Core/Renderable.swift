//
//  Renderable.swift
//
//
//  Created by Reza Ali on 4/19/22.
//

import Metal
import simd

open class Renderable : Object {
    /// Which of a renderable's materials draw in one pass. `includes(_:)` is the one decision both
    /// routing (which passes a renderable is recorded in) and drawing (which of its submeshes draw
    /// in a pass) use, so a material draws in exactly one transparent pass.
    enum MaterialPass {
        case all
        case opaque
        /// Alpha blending accumulated order-independently. Only recorded by encoders with OIT.
        case alphaTransparent
        /// Every other transparent material: all of them when `excludesAlphaOit` is false (an
        /// encoder without OIT), otherwise those `alphaTransparent` doesn't take.
        case classicTransparent(excludesAlphaOit: Bool)
        case surfaceOpaque
        case unlitOpaque

        /// Whether `material` draws with order-independent alpha where OIT is available.
        static func drawsWithAlphaOit(_ material: Material) -> Bool {
            material.blending == .alpha && material.supportsAlphaOrderIndependentTransparency
        }

        func includes(_ material: Material) -> Bool {
            let isTransparent = material.blending != .disabled
            switch self {
            case .all:
                return true
            case .opaque:
                return !isTransparent
            case .alphaTransparent:
                return Self.drawsWithAlphaOit(material)
            case let .classicTransparent(excludesAlphaOit):
                return isTransparent && !(excludesAlphaOit && Self.drawsWithAlphaOit(material))
            case .surfaceOpaque:
                return material.lightingModel == .surface && !isTransparent
            case .unlitOpaque:
                return material.lightingModel == .unlit && !isTransparent
            }
        }
    }

    open var opaque: Bool { material!.blending == .disabled }
    
    open var doubleSided: Bool = false

    open var renderOrder = 0

    open var renderLayer: RenderLayer = .opaque
    
    open var lighting: Bool { material?.lighting ?? false }


    open var receiveShadow = false

    open var castShadow = false


    open var cullMode: MTLCullMode = .back

    open var windingOrder: MTLWinding = .counterClockwise
    
    open var triangleFillMode: MTLTriangleFillMode = .fill
    
    // MARK: - Occurrences and Motion

    /// What one occurrence of this renderable draws with: its model and normal matrices, and the
    /// model matrix the same occurrence had last frame, for motion. Every pass of the occurrence
    /// (shadow lights, faces, colour) reads it; only the engine advances it.
    struct Occurrence {
        var modelMatrix: simd_float4x4
        var normalMatrix: simd_float3x3
        var previousModelMatrix: simd_float4x4
        /// Counts this renderable's occurrences, for snapshots taken once per occurrence and shared
        /// by its passes.
        var serial: Int
    }

    private(set) var occurrence = Occurrence(
        modelMatrix: matrix_identity_float4x4,
        normalMatrix: matrix_identity_float3x3,
        previousModelMatrix: matrix_identity_float4x4,
        serial: 0
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

        let modelMatrix = worldMatrix
        let ordinal = currentFrameModelMatrices.count
        let previousModelMatrix = ordinal < previousFrameModelMatrices.count ? previousFrameModelMatrices[ordinal] : modelMatrix
        currentFrameModelMatrices.append(modelMatrix)

        occurrence = Occurrence(
            modelMatrix: modelMatrix,
            normalMatrix: normalMatrix,
            previousModelMatrix: previousModelMatrix,
            serial: occurrence.serial &+ 1
        )
    }

    /// Forgets this renderable's motion: its next occurrences draw with none. For an owner whose
    /// drawing changed in a way ordinals can't see, such as a reordered or resized set of draws.
    open func resetMotion() {
        previousFrameModelMatrices.removeAll(keepingCapacity: true)
        currentFrameModelMatrices.removeAll(keepingCapacity: true)
    }

    open var material: Material? = nil
    open var materials: [Material] = []

    /// Records this renderable's draw for one render event: its bindings, material and geometry
    /// draws, and any custom commands. Recorded values are captured, so later changes don't affect
    /// this draw. Recording no draw call means it doesn't draw in this pass.
    open func draw(in context: RenderableDrawContext) {
        fatalError("Subclasses must implement this method")
    }
}
