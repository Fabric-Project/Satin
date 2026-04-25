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

    public var view: MetalView? {
        willSet {
            disable()
        }
        didSet {
            enable()
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

    public var target = Object(label: "Orbit Perspective Camera Controller Target")

    public var mouseDeltaSensitivity: Float = 600.0
    public var scrollDeltaSensitivity: Float = 600.0

    // MARK: - Events

    public let onStartPublisher = PassthroughSubject<OrbitPerspectiveCameraController, Never>()
    public let onChangePublisher = PassthroughSubject<OrbitPerspectiveCameraController, Never>()
    public let onEndPublisher = PassthroughSubject<OrbitPerspectiveCameraController, Never>()

    // MARK: - Internal State & Event Handling

    private var azimuthRotationFlip: Float = 1.0
    private var rotationDelta: simd_float2 = .zero
    private var azimuthRotationTotal: Float = .zero
    private var elevationRotationTotal: Float = .zero

    private var translation: simd_float3 = .zero
    private var zoom: Float = 0.0

    private var previousPosition: simd_float2 = .zero

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

    private var magnification: Float = 1.0
    private var magnifyGestureRecognizer: NSMagnificationGestureRecognizer?

#else

    private var panCurrentPoint: simd_float2 = .zero
    private var panPreviousPoint: simd_float2 = .zero
    private var panGestureRecognizer: UIPanGestureRecognizer?

    private var rotateGestureRecognizer: UIPanGestureRecognizer?

    private var pinchScale: Float = 1.0
    private var pinchGestureRecognizer: UIPinchGestureRecognizer?

    private var tapGestureRecognizer: UITapGestureRecognizer?

#endif

    // MARK: - Init

    public init(camera: PerspectiveCamera, view: MetalView) {
        self.camera = camera
        self.view = view

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

        guard state == .tweening else { return }

        var changed = false

        changed = changed || tweenTranslation()
        changed = changed || tweenZoom()
        changed = changed || tweenRotation()

        if !changed { state = .inactive }
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

        _reset()

        onStartPublisher.send(self)
        onChangePublisher.send(self)
        onEndPublisher.send(self)
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

    private func pan(_ delta: simd_float2) {
        guard let view = view else { return }

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

        translation.x = right
        translation.y = up
        updateTranslation()
    }

    // MARK: - Helpers

    private func halt() {
        state = .inactive
        rotationDelta = .zero
        translation = .zero
        zoom = 0.0
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
        guard let view = view else { return }

#if os(macOS)

        leftMouseDownHandler = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown,
            handler: mouseDown
        )

        leftMouseDraggedHandler = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDragged,
            handler: mouseDragged
        )

        leftMouseUpHandler = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseUp,
            handler: mouseUp
        )

        rightMouseDownHandler = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseDown,
            handler: rightMouseDown
        )

        rightMouseDraggedHandler = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseDragged,
            handler: rightMouseDragged
        )

        rightMouseUpHandler = NSEvent.addLocalMonitorForEvents(
            matching: .rightMouseUp,
            handler: rightMouseUp
        )

        otherMouseDownHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseDown,
            handler: otherMouseDown
        )

        otherMouseDraggedHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseDragged,
            handler: otherMouseDragged
        )

        otherMouseUpHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseUp,
            handler: otherMouseUp
        )

        scrollWheelHandler = NSEvent.addLocalMonitorForEvents(
            matching: .scrollWheel,
            handler: scrollWheel
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

    private func disableEvents() {
        guard let view else { return }

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
            otherMouseDraggedHandler = nil
        }

        if let scrollWheelHandler {
            NSEvent.removeMonitor(scrollWheelHandler)
            self.scrollWheelHandler = nil
        }

        if let magnifyGestureRecognizer {
            view.removeGestureRecognizer(magnifyGestureRecognizer)
            self.magnifyGestureRecognizer = nil
        }

#else

        if let rotateGestureRecognizer {
            view.removeGestureRecognizer(rotateGestureRecognizer)
            self.rotateGestureRecognizer = nil
        }
        if let panGestureRecognizer {
            view.removeGestureRecognizer(panGestureRecognizer)
            self.panGestureRecognizer = nil
        }
        if let tapGestureRecognizer {
            view.removeGestureRecognizer(tapGestureRecognizer)
            self.tapGestureRecognizer = nil
        }
        if let pinchGestureRecognizer {
            view.removeGestureRecognizer(pinchGestureRecognizer)
            self.pinchGestureRecognizer = nil
        }

#endif
    }

    // MARK: - Mouse

#if os(macOS)

    private func mouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window else { return event }

        if event.clickCount == 2 {
            reset()
        } else {
            halt()

            let currentPosition = view.convert(event.locationInWindow, from: nil).float2
            defer { previousPosition = currentPosition }

            state = .rotating

            updateAzimuthRotationFlip(ndc: normalizePoint(currentPosition, view.frame.size.float2))
        }

        return event
    }

    private func mouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, state == .rotating else { return event }

        let currentPosition = view.convert(event.locationInWindow, from: nil).float2
        defer { previousPosition = currentPosition }

        rotationDelta = previousPosition - currentPosition
        updateRotation(delta: rotationDelta)

        return event
    }

    private func mouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, state == .rotating else { return event }
        state = .tweening
        return event
    }

    // MARK: - Right Mouse

    private func rightMouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window else { return event }
        if event.modifierFlags.contains(NSEvent.ModifierFlags.option) {
            state = .dollying
        } else {
            state = .zooming
        }
        return event
    }

    private func rightMouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, state == .zooming || state == .dollying else { return event }
        let dy = Float(event.deltaY) / mouseDeltaSensitivity
        if state == .dollying {
            translation.z = dy * translationScalar
            updateTranslation()
        } else if state == .zooming {
            zoom = -dy
            updateZoom()
        }
        return event
    }

    private func rightMouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, state == .zooming || state == .dollying else { return event }
        state = .tweening
        return event
    }

    // MARK: - Other Mouse

    private func otherMouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window else { return event }
        state = .panning
        return event
    }

    private func otherMouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, state == .panning else { return event }
        pan(simd_make_float2(Float(event.deltaX), Float(event.deltaY)))
        return event
    }

    private func otherMouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, state == .panning else { return event }
        state = .tweening
        return event
    }

    // MARK: - Scroll Wheel

    private func scrollWheel(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window else { return event }

        if event.phase == .began { state = .panning }

        guard state == .panning else { return event }

        if event.phase == .changed {
            pan(simd_make_float2(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY)))
        } else if event.phase == .ended {
            state = .tweening
        }

        return event
    }

    // MARK: - macOS Gestures

    @MainActor
    @objc private func magnifyGesture(_ gestureRecognizer: NSMagnificationGestureRecognizer) {
        let newMagnification = Float(gestureRecognizer.magnification)

        if gestureRecognizer.state == .began {
            state = .zooming
            magnification = newMagnification
        }

        guard state == .zooming else { return }

        if gestureRecognizer.state == .changed {
            let velocity = newMagnification - magnification
            zoom = -velocity
            magnification = newMagnification
            updateZoom()
        } else if gestureRecognizer.state == .ended {
            state = .tweening
        }
    }

#else

    @objc private func tapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .ended { reset() }
    }

    @objc private func rotateGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let view = view else { return }

        if gestureRecognizer.state == .began {
            halt()
            state = .rotating
            previousPosition = gestureRecognizer.location(in: view).float2
            updateAzimuthRotationFlip(ndc: normalizePoint(previousPosition, view.frame.size.float2))
        }

        guard state == .rotating else { return }

        if gestureRecognizer.state == .changed {
            let currentPosition = gestureRecognizer.location(in: view).float2
            updateAzimuthRotationFlip(ndc: normalizePoint(currentPosition, view.frame.size.float2))

            defer { previousPosition = currentPosition }

            rotationDelta.y = currentPosition.y - previousPosition.y
            rotationDelta.x = previousPosition.x - currentPosition.x

            updateRotation(delta: rotationDelta)

        } else if gestureRecognizer.state == .ended {
            state = .tweening
        }
    }

    @objc private func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        if gestureRecognizer.state == .began {
            state = .panning
            let translation = gestureRecognizer.translation(in: view)
            panPreviousPoint = simd_make_float2(Float(translation.x), Float(translation.y))
        }

        guard state == .panning else { return }
        if gestureRecognizer.state == .changed {
            let translation = gestureRecognizer.translation(in: view)
            panCurrentPoint = simd_make_float2(Float(translation.x), Float(translation.y))
            pan(panCurrentPoint - panPreviousPoint)
            panPreviousPoint = panCurrentPoint

        } else if gestureRecognizer.state == .ended {
            state = .tweening
        }
    }

    @objc private func pinchGesture(_ gestureRecognizer: UIPinchGestureRecognizer) {
        if gestureRecognizer.state == .began {
            state = .zooming
            pinchScale = Float(gestureRecognizer.scale)
        }

        guard state == .zooming else { return }

        if gestureRecognizer.state == .changed {
            let newScale = Float(gestureRecognizer.scale)
            let delta = pinchScale - newScale
            if abs(delta) > 0.0 {
                zoom = delta
                updateZoom()
                pinchScale = newScale
            }
        } else if gestureRecognizer.state == .ended {
            state = .tweening
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
}
