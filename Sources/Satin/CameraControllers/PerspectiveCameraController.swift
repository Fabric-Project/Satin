//
//  PerspectiveCameraController.swift
//  Satin
//
//  Created by Reza Ali on 03/26/23.
//

import Combine
import MetalKit
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class PerspectiveCameraController: CameraController, Codable {
    public internal(set) var isEnabled = false

    public var camera: PerspectiveCamera {
        willSet {
            disable()
        }
        didSet {
            enable()
        }
    }

    private weak var _view: MetalView?
    public var view: MetalView? {
        get {
            _view
        }
        set {
            guard _view !== newValue else { return }

            disable()
            _view = newValue

            if newValue != nil {
                enable()
            }
        }
    }

    private var oldState: CameraControllerState = .inactive
    public internal(set) var state: CameraControllerState = .inactive {
        didSet {
            if oldValue == .inactive, state != .inactive, state != .tweening {
                onStartPublisher.send(self)
            } else if oldValue == .tweening, state == .inactive {
                onEndPublisher.send(self)
            }
            oldState = oldValue
        }
    }

    // Rotation
    public var rotationDamping: Float = 0.9
    public var rotationScalar: Float = 3.0

    // Translation (Panning & Dolly)
    public var translationDamping: Float = 0.9
    public var translationScalar: Float = 1.0

    // Zoom
    public var zoomScalar: Float = 1.0
    public var zoomDamping: Float = 0.9
    public var minimumZoomDistance: Float = 1.0 {
        didSet {
            if minimumZoomDistance < 1.0 {
                minimumZoomDistance = oldValue
            }
        }
    }

    // Roll
    public var rollScalar: Float = 1.0
    public var rollDamping: Float = 0.9

    public var defaultDistance: Float = 3.0
    public var defaultPosition: simd_float3 = simd_make_float3(0.0, 0.0, 1.0)
    public var defaultOrientation: simd_quatf = simd_quaternion(matrix_identity_float4x4)

    public lazy var target: Object = Object(context: camera.context, label: "Perspective Camera Controller Target")

    public var mouseDeltaSensitivity: Float = 600.0
    public var scrollDeltaSensitivity: Float = 600.0

    // MARK: - Events

    public let onStartPublisher = PassthroughSubject<PerspectiveCameraController, Never>()
    public let onChangePublisher = PassthroughSubject<PerspectiveCameraController, Never>()
    public let onEndPublisher = PassthroughSubject<PerspectiveCameraController, Never>()

    // MARK: - Internal State & Event Handling

    private struct InputState {
        var interactionState: CameraControllerState = .inactive
        var transitionToTweeningAfterPendingInput = false
        var requestReset = false
        var requestHalt = false

        var pendingRotationAxis: simd_float3 = .zero
        var pendingRotationAngle: Float = 0.0
        var pendingRotation: simd_quatf = simd_quatf(matrix_identity_float4x4)
        var pendingPanDelta: simd_float2 = .zero
        var pendingDollyDelta: Float = 0.0
        var pendingZoom: Float = 0.0
        var pendingRoll: Float = 0.0
        var previousPosition: simd_float2 = .zero

#if os(macOS)
        var magnification: Float = 1.0
#else
        var rollRotation: Float = 0.0
        var panCurrentPoint: simd_float2 = .zero
        var panPreviousPoint: simd_float2 = .zero
        var pinchScale: Float = 1.0
#endif
    }

    private struct DrainedInput {
        var interactionState: CameraControllerState
        var transitionToTweeningAfterPendingInput: Bool
        var requestReset: Bool
        var requestHalt: Bool
        var pendingRotationAxis: simd_float3
        var pendingRotationAngle: Float
        var pendingRotation: simd_quatf
        var pendingPanDelta: simd_float2
        var pendingDollyDelta: Float
        var pendingZoom: Float
        var pendingRoll: Float
    }

    private let inputState = ControllerInputMailbox(InputState())

    private var rotationAxis: simd_float3 = .zero
    private var rotationAngle: Float = 0.0

    private var translation: simd_float3 = .zero
    private var zoom: Float = 0.0
    private var roll: Float = 0.0

    private var deltaTime: Float = .zero
    private lazy var previousTime: TimeInterval = getTime()

#if os(macOS)

    private var leftMouseDownHandler: Any?
    private var leftMouseDraggedHandler: Any?
    private var leftMouseUpHandler: Any?

    private var rightMouseDownHandler: Any?
    private var rightMouseDraggedHandler: Any?
    private var rightMouseUpHandler: Any?

    private var otherMouseDownHandler: Any?
    private var otherMouseDraggedHandler: Any?
    private var otherMouseUpHandler: Any?

    private var scrollWheelHandler: Any?

    private var magnifyGestureRecognizer: NSMagnificationGestureRecognizer!
    private var rollGestureRecognizer: NSRotationGestureRecognizer!

#else
    private var rollGestureRecognizer: UIRotationGestureRecognizer!
    private var panGestureRecognizer: UIPanGestureRecognizer!

    private var rotateGestureRecognizer: UIPanGestureRecognizer!
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!

    private var tapGestureRecognizer: UITapGestureRecognizer!

#endif

    // MARK: - Init

    public init(camera: PerspectiveCamera, view: MetalView) {
        self.camera = camera
        _view = view

        defaultDistance = simd_length(camera.position)
        defaultPosition = camera.position
        defaultOrientation = camera.orientation

        enable()
    }

    deinit {
        disable()
    }

    // MARK: - Update

    public func update() {
        updateTime()

        let drainedInput = drainInputState()

        if drainedInput.requestHalt {
            halt()
            return
        }

        if drainedInput.requestReset {
            performReset()
            return
        }

        if state != drainedInput.interactionState {
            state = drainedInput.interactionState
        }

        _ = applyPendingInput(drainedInput)

        if drainedInput.transitionToTweeningAfterPendingInput {
            state = .tweening
            setInteractionState(.tweening)
            return
        }

        if state != .tweening {
            return
        }

        var changed = false

        changed = changed || tweenTranslation()
        changed = changed || tweenZoom()
        changed = changed || tweenRotation()
        changed = changed || tweenRoll()

        if !changed {
            state = .inactive
            setInteractionState(.inactive)
        }
    }

    // MARK: - Enable

    public func enable() {
        guard !isEnabled else { return }

        enableEvents()

        halt()

        resetCameraAndTarget()

        target.add(camera)

        isEnabled = true
    }

    // MARK: - Disable

    public func disable() {
        guard isEnabled else { return }

        disableEvents()

        halt()

        let cameraWorldMatrix = camera.worldMatrix
        target.remove(camera)
        camera.localMatrix = cameraWorldMatrix

        isEnabled = false
    }

    // MARK: - Reset

    public func reset() {
        guard isEnabled else { return }
        performReset()
    }

    private func resetCameraAndTarget() {
        clearInputState()

        let defaultForward = simd_make_float3(0, 0, defaultDistance)

        camera.position = defaultForward
        camera.orientation = simd_quatf(matrix_identity_float4x4)

        target.position = defaultPosition - defaultOrientation.act(defaultForward)
        target.orientation = defaultOrientation
    }

    // MARK: - Resize

    public func resize(_ size: (width: Float, height: Float)) {
        camera.aspect = size.width / size.height
    }

    // MARK: - Save & Load

    public func save(url: URL) {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let payload: Data = try jsonEncoder.encode(self)
            try payload.write(to: url)
        } catch {
            print(error.localizedDescription)
        }
    }

    public func load(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode(PerspectiveCameraController.self, from: data)
            target.setFrom(object: loaded.target)
            camera.setFrom(object: loaded.camera)
            clearInputState()
        } catch {
            print(error.localizedDescription)
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        camera = try values.decode(PerspectiveCamera.self, forKey: .camera)
        target = try values.decode(Object.self, forKey: .target)
        mouseDeltaSensitivity = try values.decode(Float.self, forKey: .mouseDeltaSensitivity)
        scrollDeltaSensitivity = try values.decode(Float.self, forKey: .scrollDeltaSensitivity)
        rotationDamping = try values.decode(Float.self, forKey: .rotationDamping)
        rotationScalar = try values.decode(Float.self, forKey: .rotationScalar)
        translationDamping = try values.decode(Float.self, forKey: .translationDamping)
        translationScalar = try values.decode(Float.self, forKey: .translationScalar)
        zoomScalar = try values.decode(Float.self, forKey: .zoomScalar)
        zoomDamping = try values.decode(Float.self, forKey: .zoomDamping)
        rollScalar = try values.decode(Float.self, forKey: .rollScalar)
        rollDamping = try values.decode(Float.self, forKey: .rollDamping)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(camera, forKey: .camera)
        try container.encode(target, forKey: .target)
        try container.encode(mouseDeltaSensitivity, forKey: .mouseDeltaSensitivity)
        try container.encode(scrollDeltaSensitivity, forKey: .scrollDeltaSensitivity)
        try container.encode(rotationDamping, forKey: .rotationDamping)
        try container.encode(rotationScalar, forKey: .rotationScalar)
        try container.encode(translationDamping, forKey: .translationDamping)
        try container.encode(translationScalar, forKey: .translationScalar)
        try container.encode(zoomScalar, forKey: .zoomScalar)
        try container.encode(zoomDamping, forKey: .zoomDamping)
        try container.encode(rollScalar, forKey: .rollScalar)
        try container.encode(rollDamping, forKey: .rollDamping)
    }

    private enum CodingKeys: String, CodingKey {
        case camera
        case target
        case mouseDeltaSensitivity
        case scrollDeltaSensitivity
        case rotationDamping
        case rotationScalar
        case translationDamping
        case translationScalar
        case zoomScalar
        case zoomDamping
        case rollScalar
        case rollDamping
    }

    // MARK: - Camera Transform Updates

    private func updateRotation() {
        guard !rotationAxis.x.isNaN, !rotationAxis.y.isNaN, !rotationAxis.z.isNaN, !rotationAngle.isNaN else { return }
        target.orientation *= simd_quatf(angle: rotationScalar * rotationAngle, axis: rotationAxis)
        onChangePublisher.send(self)
    }

    private func tweenRotation() -> Bool {
        guard oldState == .rotating, abs(rotationAngle) > 0.001 else { return false }
        rotationAngle *= rotationDamping
        updateRotation()
        return true
    }

    private func updateRoll() {
        guard !roll.isNaN else { return }
        target.orientation = simd_mul(target.orientation, simd_quatf(angle: rollScalar * roll, axis: camera.forwardDirection))
        onChangePublisher.send(self)
    }

    private func tweenRoll() -> Bool {
        guard oldState == .rolling, abs(roll) > 0.001 else { return false }
        roll *= rollDamping
        updateRoll()
        return true
    }

    private func updateZoom() {
        let zoomAmount = zoom * zoomScalar * (180.0 / camera.fov) * (pow(simd_length(camera.worldPosition), 0.5) + 1.0)
        camera.position.z += zoomAmount
        onChangePublisher.send(self)
    }

    private func tweenZoom() -> Bool {
        guard oldState == .zooming, abs(zoom) > 0.001 else { return false }
        zoom *= zoomDamping
        updateZoom()
        return true
    }

    private func updateTranslation() {
        target.position = translationScalar * target.position + simd_make_float3(target.forwardDirection * translation.z)
        target.position = translationScalar * target.position - simd_make_float3(target.rightDirection * translation.x)
        target.position = translationScalar * target.position + simd_make_float3(target.upDirection * translation.y)
        onChangePublisher.send(self)
    }

    private func tweenTranslation() -> Bool {
        guard oldState == .panning || oldState == .dollying, simd_length(translation) > 0.001 else { return false }
        translation *= translationDamping
        updateTranslation()
        return true
    }

    private func resolvePan(_ delta: simd_float2) -> simd_float3 {
        guard let view = view else { return .zero }

        var pan = delta

        let width = Float(view.frame.width)
        let height = Float(view.frame.height)
        let aspect = width / height
        pan.x /= width
        pan.y /= height

        let imagePlaneHeight = (180.0 / camera.fov) * (pow(simd_length(camera.worldPosition), 0.25) + 1.0)
        let imagePlaneWidth = aspect * imagePlaneHeight

        return simd_float3(pan.x * imagePlaneWidth, pan.y * imagePlaneHeight, 0.0)
    }

    // MARK: - Helpers

    private func halt() {
        state = .inactive
        setInteractionState(.inactive)
        rotationAngle = 0.0
        translation = .zero
        zoom = 0.0
        roll = 0.0
        clearInputState()
    }

    @discardableResult
    private func applyPendingInput(_ input: DrainedInput) -> Bool {
        switch state {
        case .rotating:
            guard abs(input.pendingRotationAngle) > 0.0 else { return false }
            rotationAxis = input.pendingRotationAxis
            rotationAngle = input.pendingRotationAngle
            target.orientation *= input.pendingRotation
            onChangePublisher.send(self)
            return true

        case .panning:
            guard input.pendingPanDelta != .zero else { return false }
            translation = resolvePan(input.pendingPanDelta)
            updateTranslation()
            return true

        case .dollying:
            guard abs(input.pendingDollyDelta) > 0.0 else { return false }
            translation = simd_float3(0.0, 0.0, input.pendingDollyDelta * translationScalar)
            updateTranslation()
            return true

        case .zooming:
            guard abs(input.pendingZoom) > 0.0 else { return false }
            zoom = input.pendingZoom
            updateZoom()
            return true

        case .rolling:
            guard abs(input.pendingRoll) > 0.0 else { return false }
            roll = input.pendingRoll
            updateRoll()
            return true

        default:
            return false
        }
    }

    private func beginTweeningIfNeeded() {
        inputState.withState { state in
            if abs(state.pendingRotationAngle) > 0.0 ||
                state.pendingPanDelta != .zero ||
                abs(state.pendingDollyDelta) > 0.0 ||
                abs(state.pendingZoom) > 0.0 ||
                abs(state.pendingRoll) > 0.0
            {
                state.transitionToTweeningAfterPendingInput = true
            } else {
                state.interactionState = .tweening
            }
        }
    }

    private func requestHalt() {
        inputState.withState { state in
            state.requestHalt = true
            state.interactionState = .inactive
            state.transitionToTweeningAfterPendingInput = false
            state.pendingRotationAxis = .zero
            state.pendingRotationAngle = 0.0
            state.pendingRotation = simd_quatf(angle: 0.0, axis: Satin.worldUpDirection)
            state.pendingPanDelta = .zero
            state.pendingDollyDelta = 0.0
            state.pendingZoom = 0.0
            state.pendingRoll = 0.0
        }
    }

    private func setInteractionState(_ interactionState: CameraControllerState) {
        inputState.withState { state in
            state.interactionState = interactionState
        }
    }

    private func clearInputState() {
        inputState.withState { state in
            state = InputState()
        }
    }

    private func drainInputState() -> DrainedInput {
        inputState.withState { state in
            let drained = DrainedInput(
                interactionState: state.interactionState,
                transitionToTweeningAfterPendingInput: state.transitionToTweeningAfterPendingInput,
                requestReset: state.requestReset,
                requestHalt: state.requestHalt,
                pendingRotationAxis: state.pendingRotationAxis,
                pendingRotationAngle: state.pendingRotationAngle,
                pendingRotation: state.pendingRotation,
                pendingPanDelta: state.pendingPanDelta,
                pendingDollyDelta: state.pendingDollyDelta,
                pendingZoom: state.pendingZoom,
                pendingRoll: state.pendingRoll
            )

            state.transitionToTweeningAfterPendingInput = false
            state.requestReset = false
            state.requestHalt = false
            state.pendingRotationAxis = .zero
            state.pendingRotationAngle = 0.0
            state.pendingRotation = simd_quatf(matrix_identity_float4x4)
            state.pendingPanDelta = .zero
            state.pendingDollyDelta = 0.0
            state.pendingZoom = 0.0
            state.pendingRoll = 0.0

            return drained
        }
    }

    private func performReset() {
        halt()
        resetCameraAndTarget()
        onStartPublisher.send(self)
        onChangePublisher.send(self)
        onEndPublisher.send(self)
    }

    private func normalizePoint(_ point: simd_float2, _ size: simd_float2) -> simd_float2 {
#if os(macOS)
        return 2.0 * (point / size) - 1.0
#else
        var result = point / size
        result.y = 1.0 - result.y
        return 2.0 * result - 1.0
#endif
    }

    private func getTrackBallAngleAxis(previousPosition: simd_float2, currentPosition: simd_float2, size: simd_float2) -> (angle: Float, axis: simd_float3)? {
        let previous = simd_normalize(trackBallPoint(previousPosition, size))
        let current = simd_normalize(trackBallPoint(currentPosition, size))

        let angle = acos(simd_dot(previous, current))
        let axis = simd_normalize(-simd_cross(previous, current))

        if !angle.isNaN, !axis.x.isNaN, !axis.y.isNaN, !axis.z.isNaN {
            return (angle, axis)
        }
        return nil
    }

    private func trackBallPoint(_ point: simd_float2, _ size: simd_float2) -> simd_float3 {
        let pt = normalizePoint(point, size) * size * 0.5

        let radius = 0.5 * simd_max(size.x, size.y)
        let radius2 = radius * radius
        let radiusOverSqrt2 = radius / sqrt(2.0)

        let xyLen = simd_length(pt)
        if xyLen < radiusOverSqrt2 {
            return simd_make_float3(pt.x, pt.y, sqrt(radius2 - xyLen * xyLen))
        } else {
            return simd_make_float3(pt.x, pt.y, radius2 / (2.0 * xyLen))
        }
    }

    // MARK: - Events

    private func enableEvents() {
        cameraControllerPerformUIWork {
            guard let view = view else { return }

#if os(macOS)

        leftMouseDownHandler = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown,
            handler: { [weak self] event in
                self?.mouseDown(with: event) ?? event
            }
        )

        leftMouseDraggedHandler = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDragged,
            handler: { [weak self] event in
                self?.mouseDragged(with: event) ?? event
            }
        )

        leftMouseUpHandler = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseUp,
            handler: { [weak self] event in
                self?.mouseUp(with: event) ?? event
            }
        )

        rightMouseDownHandler = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseDown,
            handler: { [weak self] event in
                self?.rightMouseDown(with: event) ?? event
            }
        )

        rightMouseDraggedHandler = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseDragged,
            handler: { [weak self] event in
                self?.rightMouseDragged(with: event) ?? event
            }
        )

        rightMouseUpHandler = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseUp,
            handler: { [weak self] event in
                self?.rightMouseUp(with: event) ?? event
            }
        )

        otherMouseDownHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseDown,
            handler: { [weak self] event in
                self?.otherMouseDown(with: event) ?? event
            }
        )

        otherMouseDraggedHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseDragged,
            handler: { [weak self] event in
                self?.otherMouseDragged(with: event) ?? event
            }
        )

        otherMouseUpHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseUp,
            handler: { [weak self] event in
                self?.otherMouseUp(with: event) ?? event
            }
        )

        scrollWheelHandler = NSEvent.addLocalMonitorForEvents(
            matching: .scrollWheel,
            handler: { [weak self] event in
                self?.scrollWheel(with: event) ?? event
            }
        )

        magnifyGestureRecognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(magnifyGesture))
        view.addGestureRecognizer(magnifyGestureRecognizer)

        rollGestureRecognizer = NSRotationGestureRecognizer(target: self, action: #selector(rollGesture))
        view.addGestureRecognizer(rollGestureRecognizer)

#else

        view.isMultipleTouchEnabled = true

        let allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        rotateGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(rotateGesture))
        rotateGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        rotateGestureRecognizer.minimumNumberOfTouches = 1
        rotateGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(rotateGestureRecognizer)

        rollGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(rollGesture))
        rollGestureRecognizer.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        view.addGestureRecognizer(rollGestureRecognizer)

        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        panGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        panGestureRecognizer.minimumNumberOfTouches = 2
        panGestureRecognizer.maximumNumberOfTouches = 2
        view.addGestureRecognizer(panGestureRecognizer)

        tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapGesture))
        tapGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        tapGestureRecognizer.numberOfTouchesRequired = 1
        tapGestureRecognizer.numberOfTapsRequired = 2
        view.addGestureRecognizer(tapGestureRecognizer)

        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchGesture))
        pinchGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        view.addGestureRecognizer(pinchGestureRecognizer)

#endif
        }
    }

    private func disableEvents() {
        cameraControllerPerformUIWork {
            let view = view

#if os(macOS)

        if let leftMouseDownHandler {
            NSEvent.removeMonitor(leftMouseDownHandler)
            self.leftMouseDownHandler = nil
        }
        if let leftMouseDraggedHandler {
            NSEvent.removeMonitor(leftMouseDraggedHandler)
            self.leftMouseDraggedHandler = nil
        }
        if let leftMouseUpHandler {
            NSEvent.removeMonitor(leftMouseUpHandler)
            self.leftMouseUpHandler = nil
        }
        if let rightMouseDownHandler {
            NSEvent.removeMonitor(rightMouseDownHandler)
            self.rightMouseDownHandler = nil
        }
        if let rightMouseDraggedHandler {
            NSEvent.removeMonitor(rightMouseDraggedHandler)
            self.rightMouseDraggedHandler = nil
        }
        if let rightMouseUpHandler {
            NSEvent.removeMonitor(rightMouseUpHandler)
            self.rightMouseUpHandler = nil
        }
        if let otherMouseDownHandler {
            NSEvent.removeMonitor(otherMouseDownHandler)
            self.otherMouseDownHandler = nil
        }
        if let otherMouseDraggedHandler {
            NSEvent.removeMonitor(otherMouseDraggedHandler)
            self.otherMouseDraggedHandler = nil
        }
        if let otherMouseUpHandler {
            NSEvent.removeMonitor(otherMouseUpHandler)
            self.otherMouseUpHandler = nil
        }
        if let scrollWheelHandler {
            NSEvent.removeMonitor(scrollWheelHandler)
            self.scrollWheelHandler = nil
        }

        if let magnifyGestureRecognizer {
            view?.removeGestureRecognizer(magnifyGestureRecognizer)
            self.magnifyGestureRecognizer = nil
        }
        if let rollGestureRecognizer {
            view?.removeGestureRecognizer(rollGestureRecognizer)
            self.rollGestureRecognizer = nil
        }

#else

        if let rotateGestureRecognizer {
            view?.removeGestureRecognizer(rotateGestureRecognizer)
            self.rotateGestureRecognizer = nil
        }
        if let rollGestureRecognizer {
            view?.removeGestureRecognizer(rollGestureRecognizer)
            self.rollGestureRecognizer = nil
        }
        if let panGestureRecognizer {
            view?.removeGestureRecognizer(panGestureRecognizer)
            self.panGestureRecognizer = nil
        }
        if let tapGestureRecognizer {
            view?.removeGestureRecognizer(tapGestureRecognizer)
            self.tapGestureRecognizer = nil
        }
        if let pinchGestureRecognizer {
            view?.removeGestureRecognizer(pinchGestureRecognizer)
            self.pinchGestureRecognizer = nil
        }

#endif
        }
    }

    // MARK: - Mouse

#if os(macOS)

    private func mouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerShouldBeginInteraction(event, view: view, onReject: { [weak self] in
            self?.requestHalt()
        }) else { return event }

        if event.clickCount == 2 {
            inputState.withState { state in
                state.requestReset = true
                state.interactionState = .inactive
            }
        } else {
            inputState.withState { state in
                state.previousPosition = view.convert(event.locationInWindow, from: nil).float2
                state.interactionState = .rotating
            }
        }

        return event
    }

    private func mouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window else { return event }

        let currentPosition = view.convert(event.locationInWindow, from: nil).float2
        inputState.withState { state in
            guard state.interactionState == .rotating else { return }

            defer { state.previousPosition = currentPosition }

            if let angleAxis = getTrackBallAngleAxis(
                previousPosition: state.previousPosition,
                currentPosition: currentPosition,
                size: view.frame.size.float2
            ) {
                state.pendingRotationAxis = angleAxis.axis
                state.pendingRotationAngle = angleAxis.angle
                state.pendingRotation *= simd_quatf(angle: rotationScalar * angleAxis.angle, axis: angleAxis.axis)
            }
        }

        return event
    }

    private func mouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .rotating }) else { return event }
        beginTweeningIfNeeded()
        return event
    }

    // MARK: - Right Mouse

    private func rightMouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerShouldBeginInteraction(event, view: view, onReject: { [weak self] in
            self?.requestHalt()
        }) else { return event }
        inputState.withState { state in
            state.interactionState = event.modifierFlags.contains(NSEvent.ModifierFlags.option) ? .dollying : .zooming
        }
        return event
    }

    private func rightMouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window else { return event }
        let dy = Float(event.deltaY) / mouseDeltaSensitivity
        inputState.withState { state in
            if state.interactionState == .dollying {
                state.pendingDollyDelta += dy
            } else if state.interactionState == .zooming {
                state.pendingZoom += -dy
            }
        }
        return event
    }

    private func rightMouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .zooming || $0.interactionState == .dollying }) else { return event }
        beginTweeningIfNeeded()
        return event
    }

    // MARK: - Other Mouse

    private func otherMouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerShouldBeginInteraction(event, view: view, onReject: { [weak self] in
            self?.requestHalt()
        }) else { return event }
        setInteractionState(.panning)
        return event
    }

    private func otherMouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .panning }) else { return event }
        inputState.withState { state in
            state.pendingPanDelta += simd_make_float2(Float(event.deltaX), Float(event.deltaY))
        }
        return event
    }

    private func otherMouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .panning }) else { return event }
        beginTweeningIfNeeded()
        return event
    }

    // MARK: - Scroll Wheel

    private func scrollWheel(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerEventTargetsView(event, view: view) else { return event }

        if event.phase == .began { setInteractionState(.panning) }

        guard inputState.withState({ $0.interactionState == .panning }) else { return event }

        if event.phase == .changed {
            inputState.withState { state in
                state.pendingPanDelta += simd_make_float2(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY))
            }
        } else if event.phase == .ended {
            beginTweeningIfNeeded()
        }

        return event
    }

    // MARK: - macOS Gestures

    @objc private func magnifyGesture(_ gestureRecognizer: NSMagnificationGestureRecognizer) {
        let newMagnification = Float(gestureRecognizer.magnification)

        if gestureRecognizer.state == .began {
            inputState.withState { state in
                state.interactionState = .zooming
                state.magnification = newMagnification
            }
        }

        guard inputState.withState({ $0.interactionState == .zooming }) else { return }

        if gestureRecognizer.state == .changed {
            inputState.withState { state in
                let velocity = newMagnification - state.magnification
                state.pendingZoom += -velocity
                state.magnification = newMagnification
            }
        } else if gestureRecognizer.state == .ended {
            beginTweeningIfNeeded()
        }
    }

    @objc private func rollGesture(_ gestureRecognizer: NSRotationGestureRecognizer) {
        if gestureRecognizer.state == .began { setInteractionState(.rolling) }

        guard inputState.withState({ $0.interactionState == .rolling }) else { return }

        if gestureRecognizer.state == .changed {
            inputState.withState { state in
                state.pendingRoll += -Float(gestureRecognizer.rotation)
            }
        } else if gestureRecognizer.state == .ended {
            beginTweeningIfNeeded()
        }
        gestureRecognizer.rotation = 0.0
    }

#else

    @objc private func tapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .ended {
            inputState.withState { state in
                state.requestReset = true
                state.interactionState = .inactive
            }
        }
    }

    @objc private func rollGesture(_ gestureRecognizer: UIRotationGestureRecognizer) {
        if gestureRecognizer.state == .began {
            state = .rolling
            rollRotation = Float(gestureRecognizer.rotation)
        }

        guard state == .rolling else { return }

        if gestureRecognizer.state == .changed {
            let newRotation = Float(gestureRecognizer.rotation)
            pendingRoll += newRotation - rollRotation
            rollRotation = newRotation
        } else if gestureRecognizer.state == .ended {
            beginTweeningIfNeeded()
        }
    }

    @objc private func rotateGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let view = view else { return }

        if gestureRecognizer.state == .began {
            inputState.withState { state in
                state.interactionState = .rotating
                state.previousPosition = gestureRecognizer.location(in: view).float2
            }
        }

        guard inputState.withState({ $0.interactionState == .rotating }) else { return }

        if gestureRecognizer.state == .changed {
            let currentPosition = gestureRecognizer.location(in: view).float2
            inputState.withState { state in
                defer { state.previousPosition = currentPosition }

                if let angleAxis = getTrackBallAngleAxis(
                    previousPosition: state.previousPosition,
                    currentPosition: currentPosition,
                    size: view.frame.size.float2
                ) {
                    state.pendingRotationAxis = angleAxis.axis
                    state.pendingRotationAngle = angleAxis.angle
                    state.pendingRotation *= simd_quatf(angle: rotationScalar * angleAxis.angle, axis: angleAxis.axis)
                }
            }
        } else if gestureRecognizer.state == .ended {
            beginTweeningIfNeeded()
        }
    }

    @objc private func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        if gestureRecognizer.state == .began {
            let translation = gestureRecognizer.translation(in: view)
            inputState.withState { state in
                state.interactionState = .panning
                state.panPreviousPoint = simd_make_float2(Float(translation.x), Float(translation.y))
            }
        }

        guard inputState.withState({ $0.interactionState == .panning }) else { return }
        if gestureRecognizer.state == .changed {
            let translation = gestureRecognizer.translation(in: view)
            inputState.withState { state in
                state.panCurrentPoint = simd_make_float2(Float(translation.x), Float(translation.y))
                let delta = state.panCurrentPoint - state.panPreviousPoint
                state.pendingPanDelta += delta
                state.panPreviousPoint = state.panCurrentPoint
            }

        } else if gestureRecognizer.state == .ended {
            setInteractionState(.tweening)
        }
    }

    @objc private func pinchGesture(_ gestureRecognizer: UIPinchGestureRecognizer) {
        if gestureRecognizer.state == .began {
            inputState.withState { state in
                state.interactionState = .zooming
                state.pinchScale = Float(gestureRecognizer.scale)
            }
        }

        guard inputState.withState({ $0.interactionState == .zooming }) else { return }

        if gestureRecognizer.state == .changed {
            let newScale = Float(gestureRecognizer.scale)
            inputState.withState { state in
                let delta = state.pinchScale - newScale
                if abs(delta) > 0.0 {
                    state.pendingZoom += delta
                    state.pinchScale = newScale
                }
            }
        } else if gestureRecognizer.state == .ended {
            beginTweeningIfNeeded()
        }
    }

#endif

    private func getTime() -> TimeInterval {
        return CFAbsoluteTimeGetCurrent()
    }

    private func updateTime() {
        let currentTime = getTime()
        deltaTime = Float(currentTime - previousTime)
        previousTime = currentTime
    }

    internal func queueRotationForTesting(axis: simd_float3, angle: Float) {
        inputState.withState { state in
            state.interactionState = .rotating
            state.pendingRotationAxis = axis
            state.pendingRotationAngle = angle
            state.pendingRotation *= simd_quatf(angle: rotationScalar * angle, axis: axis)
        }
    }

    internal func queueTranslationForTesting(_ translation: simd_float3, state: CameraControllerState = .panning) {
        inputState.withState { input in
            input.interactionState = state
            if state == .dollying {
                input.pendingDollyDelta = translation.z / max(translationScalar, .leastNonzeroMagnitude)
            } else {
                input.pendingPanDelta += simd_make_float2(translation.x, translation.y)
            }
        }
    }

    internal func queueZoomForTesting(_ zoom: Float) {
        inputState.withState { state in
            state.interactionState = .zooming
            state.pendingZoom = zoom
        }
    }

    internal func queueRollForTesting(_ roll: Float) {
        inputState.withState { state in
            state.interactionState = .rolling
            state.pendingRoll = roll
        }
    }
}
