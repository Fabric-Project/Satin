//
//  OrbitPerspectiveCameraController.swift
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

public final class OrbitPerspectiveCameraController: CameraController, Codable {
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
    public var rotationScalar: Float = 0.25

    // Translation (Panning & Dolly)
    public var translationDamping: Float = 0.9
    public var translationScalar: Float = 0.5

    // Zoom
    public var zoomScalar: Float = 0.5
    public var zoomDamping: Float = 0.9
    public var minimumZoomDistance: Float = 1.0 {
        didSet {
            if minimumZoomDistance < 1.0 {
                minimumZoomDistance = oldValue
            }
        }
    }

    public var defaultPosition: simd_float3 = simd_make_float3(0.0, 0.0, 1.0)
    public var defaultOrientation: simd_quatf = simd_quaternion(matrix_identity_float4x4)

    public lazy var target: Object = Object(context: camera.context, label: "Orbit Perspective Camera Controller Target")

    public var mouseDeltaSensitivity: Float = 600.0
    public var scrollDeltaSensitivity: Float = 600.0

    // MARK: - Events

    public let onStartPublisher = PassthroughSubject<OrbitPerspectiveCameraController, Never>()
    public let onChangePublisher = PassthroughSubject<OrbitPerspectiveCameraController, Never>()
    public let onEndPublisher = PassthroughSubject<OrbitPerspectiveCameraController, Never>()

    // MARK: - Internal State & Event Handling

    private struct InputState {
        var interactionState: CameraControllerState = .inactive
        var transitionToTweeningAfterPendingInput = false
        var requestReset = false
        var requestHalt = false
        var pendingRotationDelta: simd_float2 = .zero
        var pendingPanDelta: simd_float2 = .zero
        var pendingDollyDelta: Float = 0.0
        var pendingZoom: Float = 0.0
        var previousPosition: simd_float2 = .zero

#if os(macOS)
        var magnification: Float = 1.0
#else
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
        var pendingRotationDelta: simd_float2
        var pendingPanDelta: simd_float2
        var pendingDollyDelta: Float
        var pendingZoom: Float
    }

    private let inputState = ControllerInputMailbox(InputState())

    private var azimuthRotationFlip: Float = 1.0
    private var rotationDelta: simd_float2 = .zero
    private var azimuthRotationTotal: Float = .zero
    private var elevationRotationTotal: Float = .zero

    private var translation: simd_float3 = .zero
    private var zoom: Float = 0.0

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

    private var magnifyGestureRecognizer: NSMagnificationGestureRecognizer?

#else
    private var panGestureRecognizer: UIPanGestureRecognizer?

    private var rotateGestureRecognizer: UIPanGestureRecognizer?
    private var pinchGestureRecognizer: UIPinchGestureRecognizer?

    private var tapGestureRecognizer: UITapGestureRecognizer?

#endif

    // MARK: - Init

    public init(camera: PerspectiveCamera, view: MetalView) {
        self.camera = camera
        _view = view

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

        target.add(camera)

        _reset()

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

    private func _reset() {
        halt()

        target.position = .zero
        target.orientation = defaultOrientation
        camera.position = [0, 0, simd_length(defaultPosition)]
        camera.orientation = simd_quatf(matrix_identity_float4x4)

        let (azimuth, elevation) = calculateAzimuthElevationAngles()
        azimuthRotationTotal = azimuth
        elevationRotationTotal = elevation

        _updateRotation()
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
            let loaded = try JSONDecoder().decode(OrbitPerspectiveCameraController.self, from: data)
            target.setFrom(object: loaded.target)
            camera.setFrom(object: loaded.camera)
            clearInputState()

            let (azimuth, elevation) = calculateAzimuthElevationAngles()
            azimuthRotationTotal = azimuth
            elevationRotationTotal = elevation
        } catch {
            print(error.localizedDescription)
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        camera = try values.decode(PerspectiveCamera.self, forKey: .camera)
        target = try values.decode(Object.self, forKey: .target)
        defaultPosition = try values.decode(simd_float3.self, forKey: .defaultPosition)
        defaultOrientation = try values.decode(simd_quatf.self, forKey: .defaultOrientation)
        mouseDeltaSensitivity = try values.decode(Float.self, forKey: .mouseDeltaSensitivity)
        scrollDeltaSensitivity = try values.decode(Float.self, forKey: .scrollDeltaSensitivity)
        rotationDamping = try values.decode(Float.self, forKey: .rotationDamping)
        rotationScalar = try values.decode(Float.self, forKey: .rotationScalar)
        translationDamping = try values.decode(Float.self, forKey: .translationDamping)
        translationScalar = try values.decode(Float.self, forKey: .translationScalar)
        zoomScalar = try values.decode(Float.self, forKey: .zoomScalar)
        zoomDamping = try values.decode(Float.self, forKey: .zoomDamping)

        let (azimuth, elevation) = calculateAzimuthElevationAngles()
        azimuthRotationTotal = azimuth
        elevationRotationTotal = elevation
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(camera, forKey: .camera)
        try container.encode(target, forKey: .target)
        try container.encode(defaultPosition, forKey: .defaultPosition)
        try container.encode(defaultOrientation, forKey: .defaultOrientation)
        try container.encode(mouseDeltaSensitivity, forKey: .mouseDeltaSensitivity)
        try container.encode(scrollDeltaSensitivity, forKey: .scrollDeltaSensitivity)
        try container.encode(rotationDamping, forKey: .rotationDamping)
        try container.encode(rotationScalar, forKey: .rotationScalar)
        try container.encode(translationDamping, forKey: .translationDamping)
        try container.encode(translationScalar, forKey: .translationScalar)
        try container.encode(zoomScalar, forKey: .zoomScalar)
        try container.encode(zoomDamping, forKey: .zoomDamping)
    }

    private enum CodingKeys: String, CodingKey {
        case camera
        case target
        case defaultPosition
        case defaultOrientation
        case mouseDeltaSensitivity
        case scrollDeltaSensitivity
        case rotationDamping
        case rotationScalar
        case translationDamping
        case translationScalar
        case zoomScalar
        case zoomDamping
    }

    // MARK: - Camera Transform Updates

    private func updateRotation(delta: simd_float2) {
        azimuthRotationTotal += azimuthRotationFlip * rotationScalar * degToRad(delta.x)
        elevationRotationTotal += rotationScalar * degToRad(delta.y)

        if azimuthRotationTotal > Float.pi {
            azimuthRotationTotal = -Float.pi + abs(azimuthRotationTotal - Float.pi)
        } else if azimuthRotationTotal < -Float.pi {
            azimuthRotationTotal = Float.pi - abs(Float.pi + azimuthRotationTotal)
        }

        if elevationRotationTotal > Float.pi {
            elevationRotationTotal = -Float.pi + abs(elevationRotationTotal - Float.pi)
        } else if elevationRotationTotal < -Float.pi {
            elevationRotationTotal = Float.pi - abs(Float.pi + elevationRotationTotal)
        }

        _updateRotation()

//        let (calculateAzimuthRotationTotal, calculateElevationRotationTotal) = calculateAzimuthElevation()
//
//        print()
//
//        print("Azimuth Rotation: \(radToDeg(azimuthRotationTotal)) : \(radToDeg(calculateAzimuthRotationTotal))")
//        let deltaAzimuth = Int(radToDeg(azimuthRotationTotal - calculateAzimuthRotationTotal))
//        print("Delta Azimuth: \(deltaAzimuth)")
//
//        print("Elevation Rotation: \(radToDeg(elevationRotationTotal)) : \(radToDeg(calculateElevationRotationTotal))")
//        let deltaElevation = Int(radToDeg(elevationRotationTotal - calculateElevationRotationTotal))
//        print("Delta Elevation: \(deltaElevation)")

        onChangePublisher.send(self)
    }

    private func _updateRotation() {
        target.orientation = simd_quaternion(matrix_identity_float4x4)

        let azimuthRotation = simd_quatf(angle: azimuthRotationTotal, axis: Satin.worldUpDirection)
        target.orientation = azimuthRotation * target.orientation

        let elevationRotation = simd_quatf(angle: elevationRotationTotal, axis: -target.worldRightDirection)
        target.orientation = elevationRotation * target.orientation
    }

    func updateAzimuthRotationFlip(ndc: simd_float2) {
        if (camera.worldPosition.y - target.worldPosition.y) < 0 {
            azimuthRotationFlip = -1.0
        } else {
            azimuthRotationFlip = 1.0
        }
    }

    // both calculated angles vary from -pi to pi
    func calculateAzimuthElevationAngles() -> (azimuth: Float, elevation: Float) {
        let delta = camera.worldForwardDirection

        let cameraRightDot = simd_dot(camera.worldRightDirection, Satin.worldRightDirection)
        let cameraUpDot = simd_dot(camera.worldUpDirection, Satin.worldUpDirection)
//        let cameraForwardDot = simd_dot(camera.worldForwardDirection, Satin.worldForwardDirection)

        let cameraIsInverted = cameraRightDot > 0 && cameraUpDot < 0
//        if cameraIsInverted {
//            print("camera is inverted")
//        }

//        let elevationRelativeToYAxis = atan2(distXZ, delta.y)
//        print("elevationRelativeToYAxis: \(elevationRelativeToYAxis.toDegrees)")

        var azimuthAngle: Float

        if cameraIsInverted {
            azimuthAngle = -atan2(delta.x, -delta.z)
        } else {
            azimuthAngle = atan2(delta.x, delta.z)
        }

        if cameraUpDot < 0 && !cameraIsInverted {
            azimuthAngle = -Float.pi + azimuthAngle
        }

        var elevationAngle: Float = asin(delta.y)

        if cameraUpDot < 0 {
            if delta.y > 0 {
                elevationAngle = Float.pi - elevationAngle
            } else {
                elevationAngle = -Float.pi - elevationAngle
            }
        }

//        print("calculateElevationRotationTotal: \(calculateElevationRotationTotal.toDegrees)")

        return (azimuthAngle, elevationAngle)
    }

    private func tweenRotation() -> Bool {
        guard oldState == .rotating, simd_length(rotationDelta) > 0.001 else { return false }
        rotationDelta *= rotationDamping
        updateRotation(delta: rotationDelta)
        return true
    }

    private func updateZoom() {
        let zoomAmount = zoom * zoomScalar * (180.0 / camera.fov)
        target.position += target.forwardDirection * zoomAmount
        onChangePublisher.send(self)
    }

    private func tweenZoom() -> Bool {
        guard oldState == .zooming, abs(zoom) > 0.001 else { return false }
        zoom *= zoomDamping
        updateZoom()
        return true
    }

    private func updateTranslation() {
        target.position = target.position + simd_make_float3(target.forwardDirection * translation.z)
        target.position = target.position - simd_make_float3(target.rightDirection * translation.x)
        target.position = target.position + simd_make_float3(target.upDirection * translation.y)
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

        let ctd = simd_length(camera.worldPosition - target.position)
        let imagePlaneHeight = 2.0 * ctd * tan(degToRad(camera.fov * 0.5))
        let imagePlaneWidth = aspect * imagePlaneHeight

        let up = pan.y * imagePlaneHeight
        let right = pan.x * imagePlaneWidth

        return simd_float3(right, up, 0.0)
    }

    // MARK: - Helpers

    private func halt() {
        state = .inactive
        setInteractionState(.inactive)
        rotationDelta = .zero
        translation = .zero
        zoom = 0.0
        clearInputState()
    }

    @discardableResult
    private func applyPendingInput(_ input: DrainedInput) -> Bool {
        switch state {
        case .rotating:
            guard simd_length(input.pendingRotationDelta) > 0.0 else { return false }
            rotationDelta = input.pendingRotationDelta
            updateRotation(delta: rotationDelta)
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

        default:
            return false
        }
    }

    private func beginTweeningIfNeeded() {
        inputState.withState { state in
            if simd_length(state.pendingRotationDelta) > 0.0 ||
                state.pendingPanDelta != .zero ||
                abs(state.pendingDollyDelta) > 0.0 ||
                abs(state.pendingZoom) > 0.0
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
            state.pendingRotationDelta = .zero
            state.pendingPanDelta = .zero
            state.pendingDollyDelta = 0.0
            state.pendingZoom = 0.0
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
                pendingRotationDelta: state.pendingRotationDelta,
                pendingPanDelta: state.pendingPanDelta,
                pendingDollyDelta: state.pendingDollyDelta,
                pendingZoom: state.pendingZoom
            )
            state.transitionToTweeningAfterPendingInput = false
            state.requestReset = false
            state.requestHalt = false
            state.pendingRotationDelta = .zero
            state.pendingPanDelta = .zero
            state.pendingDollyDelta = 0.0
            state.pendingZoom = 0.0
            return drained
        }
    }

    private func performReset() {
        _reset()
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
        view.addGestureRecognizer(magnifyGestureRecognizer!)

#else

        view.isMultipleTouchEnabled = true

        let allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        let rotateGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(rotateGesture))
        rotateGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        rotateGestureRecognizer.minimumNumberOfTouches = 1
        rotateGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(rotateGestureRecognizer)
        self.rotateGestureRecognizer = rotateGestureRecognizer

        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        panGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        panGestureRecognizer.minimumNumberOfTouches = 2
        panGestureRecognizer.maximumNumberOfTouches = 2
        view.addGestureRecognizer(panGestureRecognizer)
        self.panGestureRecognizer = panGestureRecognizer

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapGesture))
        tapGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        tapGestureRecognizer.numberOfTouchesRequired = 1
        tapGestureRecognizer.numberOfTapsRequired = 2
        view.addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer

        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchGesture))
        pinchGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        view.addGestureRecognizer(pinchGestureRecognizer)
        self.pinchGestureRecognizer = pinchGestureRecognizer
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

#else

        if let rotateGestureRecognizer {
            view?.removeGestureRecognizer(rotateGestureRecognizer)
            self.rotateGestureRecognizer = nil
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

            updateAzimuthRotationFlip(ndc: normalizePoint(view.convert(event.locationInWindow, from: nil).float2, view.frame.size.float2))
        }

        return event
    }

    private func mouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window else { return event }

        let currentPosition = view.convert(event.locationInWindow, from: nil).float2
        inputState.withState { state in
            guard state.interactionState == .rotating else { return }
            defer { state.previousPosition = currentPosition }
            state.pendingRotationDelta += state.previousPosition - currentPosition
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

    @MainActor
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

#else

    @objc private func tapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .ended {
            inputState.withState { state in
                state.requestReset = true
                state.interactionState = .inactive
            }
        }
    }

    @objc private func rotateGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let view = view else { return }

        if gestureRecognizer.state == .began {
            let currentPosition = gestureRecognizer.location(in: view).float2
            inputState.withState { state in
                state.interactionState = .rotating
                state.previousPosition = currentPosition
            }
            updateAzimuthRotationFlip(ndc: normalizePoint(currentPosition, view.frame.size.float2))
        }

        guard inputState.withState({ $0.interactionState == .rotating }) else { return }

        if gestureRecognizer.state == .changed {
            let currentPosition = gestureRecognizer.location(in: view).float2
            inputState.withState { state in
                updateAzimuthRotationFlip(ndc: normalizePoint(currentPosition, view.frame.size.float2))
                let previousPosition = state.previousPosition
                defer { state.previousPosition = currentPosition }
                let rotationDelta = simd_make_float2(previousPosition.x - currentPosition.x, currentPosition.y - previousPosition.y)
                state.pendingRotationDelta += rotationDelta
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

    internal func queueRotationForTesting(_ delta: simd_float2) {
        inputState.withState { state in
            state.interactionState = .rotating
            state.pendingRotationDelta = delta
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
}
