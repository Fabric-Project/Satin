import Metal
import Foundation
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// A shadow draw captured while the renderable still represents this occurrence. Its bindings
/// and draw calls are ordinary packets; only the light's view uniforms are supplied at finalization.
struct RecordedShadowOccurrence {
    let packets: Range<Int>
    let occurrence: Renderable.Occurrence
    let bounds: Bounds
    let frustumCulled: Bool
}

/// A light's values and views, independent of the live light modified by the next iteration.
struct RecordedLightIdentity: Equatable {
    let record: RecordToken
    let occurrenceIndex: Int
}

final class RecordedLightOccurrence: Light {
    let identity: RecordedLightIdentity
    private let capturedType: LightType
    private let capturedData: LightData
    let projectorTexture: MTLTexture?
    let projectorMatrix: simd_float4x4?
    let projectorTransform: simd_float4x4?

    override var type: LightType { capturedType }
    override var data: LightData {
        var value = capturedData
        value.shadowInfo.x = Float(shadowIndex)
        value.shadowInfo.y = Float(projectorIndex)
        return value
    }

    init(_ light: Light, identity: RecordedLightIdentity) throws {
        self.identity = identity
        light.updateViewIfNeeded()
        capturedType = light.type
        capturedData = light.data
        if let spot = light as? SpotLight, let texture = spot.projectionTexture {
            projectorTexture = texture
            projectorMatrix = spot.projectorMatrix
            projectorTransform = simd_float4x4(textureTransform: spot.projectionTransform)
        } else {
            projectorTexture = nil
            projectorMatrix = nil
            projectorTransform = nil
        }
        super.init(context: light.context, label: light.label)
        color = light.color
        intensity = light.intensity
        localMatrix = light.worldMatrix
        castShadow = light.castShadow
        if light.castShadow && light.shadow.enabled {
            let source = light.shadow
            let captured = try RecordedShadow(source, context: light.context)
            source.adoptRecordedVersion(captured)
            shadow = captured
        }
    }

    required init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                debugDescription: "Recorded lights are runtime occurrences"))
    }

    override func updateView() {} // Captured shadow/projector cameras must not be re-aimed.
}

/// Each changing light occurrence owns its shadow destinations, including all point-light faces.
/// A deliberately cached shadow can retain its unchanged map; it is not redrawn by this snapshot.
final class RecordedShadow: Shadow {
    private let capturedReachBounds: Bounds?
    private let capturedCameras: [Camera]
    private let capturedTextures: [MTLTexture]
    private let sourceState: ShadowRecordingState
    private let sourceRevision: UInt64
    private let sourceGeneration: UInt64

    init(_ source: Shadow, context: Context) throws {
        source.prepareForDrawing(context: context)
        capturedReachBounds = source.reachBounds
        sourceState = source.recordingState
        sourceRevision = source.recordingState.revision
        sourceGeneration = source.shouldRender ? source.recordingState.captureVersion() : source.recordingState.generation
        var cameras: [Camera] = []
        var textures: [MTLTexture] = []
        for index in 0..<source.passCount {
            let sourceCamera = source.passCamera(index)
            let camera = Camera(context: context, label: sourceCamera.label)
            camera.near = sourceCamera.near
            camera.far = sourceCamera.far
            camera.viewMatrix = sourceCamera.viewMatrix
            camera.projectionMatrix = sourceCamera.projectionMatrix
            cameras.append(camera)
            guard let texture = source.passTexture(index) else { throw SubmissionError.shadowAllocationFailed }
            if source.shouldRender {
                textures.append(try makeShadowTextureVersion(of: texture, allocator: context.gpuAllocator))
            } else {
                textures.append(source.recordedVersion?.passTexture(index) ?? texture)
            }
        }
        capturedCameras = cameras
        capturedTextures = textures
        super.init(context: context, label: source.label)
        if let camera = cameras.first { self.camera = camera }
        texture = textures.first
        resolution = source.resolution
        strength = source.strength
        bias = source.bias
        normalBias = source.normalBias
        radius = source.radius
        enabled = source.enabled
        autoUpdate = source.autoUpdate
        needsUpdate = source.shouldRender
    }

    override var reachBounds: Bounds? { capturedReachBounds }
    override var textures: [MTLTexture] { capturedTextures }
    override var matrices: [simd_float4x4] { capturedCameras.map(\.viewProjectionMatrix) }
    override var viewCount: Int { capturedCameras.count }
    override var passCount: Int { capturedCameras.count }
    override func passCamera(_ passIndex: Int) -> Camera { capturedCameras[passIndex] }
    override func passTexture(_ passIndex: Int) -> MTLTexture? { capturedTextures[passIndex] }
    override func beginRecording(context: Context) throws {} // Already owns this destination version.
    override func update(light: Object) {}
    override var recordingInvalidation: ShadowRecordingInvalidation {
        ShadowRecordingInvalidation(state: sourceState, generation: sourceGeneration)
    }
    override var needsUpdate: Bool {
        get { super.needsUpdate }
        set {
            super.needsUpdate = newValue
            if !newValue { sourceState.markRecorded(revision: sourceRevision, generation: sourceGeneration) }
        }
    }
}

/// A new map for one recorded occurrence, from the context's allocator: occurrences are recorded every
/// frame, so versions come from shared heaps instead of new device allocations.
func makeShadowTextureVersion(of texture: MTLTexture, allocator: GPUAllocator) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat,
                                                              width: texture.width, height: texture.height,
                                                              mipmapped: false)
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .private
    descriptor.sampleCount = texture.sampleCount
    descriptor.textureType = texture.textureType
    guard let version = try? allocator.makeTexture(descriptor, label: texture.label ?? "Recorded Shadow") else {
        throw SubmissionError.shadowAllocationFailed
    }
    return version
}
