//
//  OrthographicCameraController.swift
//  Satin
//
//  Created by Reza Ali on 03/26/23.
//

import Combine
import MetalKit
import simd

public final class OrthographicCameraController: CameraController, Codable {
    public internal(set) var isEnabled = false

    public var camera: OrthographicCamera {
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
            isSetup = false

            if newValue != nil {
                enable()
            }
        }
    }

    public internal(set) var state: CameraControllerState = .inactive {
        didSet {
            if oldValue == .inactive, state != .inactive {
                onStartPublisher.send(self)
            } else if oldValue != .inactive, state == .inactive {
                onEndPublisher.send(self)
            }
        }
    }

    // MARK: - Events

    public let onStartPublisher = PassthroughSubject<OrthographicCameraController, Never>()
    public let onChangePublisher = PassthroughSubject<OrthographicCameraController, Never>()
    public let onEndPublisher = PassthroughSubject<OrthographicCameraController, Never>()

    private struct InputState {
        var interactionState: CameraControllerState = .inactive
        var requestReset = false
        var pendingPan: simd_float2 = .zero
        var pendingZoom: Float = 0.0
        var pendingRoll: Float = 0.0

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
        var requestReset: Bool
        var pendingPan: simd_float2
        var pendingZoom: Float
        var pendingRoll: Float
    }

    private let inputState = ControllerInputMailbox(InputState())

    private var defaultPosition = simd_make_float3(0.0, 0.0, 1.0)
    private var defaultOrientation = simd_quaternion(matrix_identity_float4x4)

    private var defaultZoom: Float = 0.5
    private var zoomDelta: Float = 0.5
    private var panDelta: simd_float2 = .zero

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

    private var isSetup = false

    public init(camera: OrthographicCamera, view: MetalView, defaultZoom: Float = 0.5) {
        self.camera = camera
        _view = view

        zoomDelta = defaultZoom
        self.defaultZoom = defaultZoom

        defaultPosition = camera.position
        defaultOrientation = camera.orientation

        setup()

        enable()
    }

    deinit {
        disable()
    }

    // MARK: - Update

    public func update() {
        setup()
        let drainedInput = drainInputState()

        if drainedInput.requestReset {
            performReset()
            return
        }

        if state != drainedInput.interactionState {
            state = drainedInput.interactionState
        }

        _ = applyPendingInput(drainedInput)
    }

    // MARK: - Enable & Disable

    public func enable() {
        guard !isEnabled else { return }

        enableEvents()

        isEnabled = true
    }

    public func disable() {
        guard isEnabled else { return }

        disableEvents()

        isEnabled = false
    }

    // MARK: - Resize

    public func resize(_ size: (width: Float, height: Float)) {
        guard let view = view, view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }

        setup()

        let cameraWidth = abs(camera.right - camera.left)
        zoomDelta = cameraWidth / Float(2.0 * view.drawableSize.width)

        let hw = size.width * zoomDelta
        let hh = size.height * zoomDelta
        camera.update(left: -hw, right: hw, bottom: -hh, top: hh, near: camera.near, far: camera.far)
    }

    // MARK: - Reset

    public func reset() {
        guard isEnabled else { return }
        performReset()
    }

    private func performReset() {
        guard let view = view else { return }

        state = .inactive
        clearInputState()

        panDelta = [0.0, 0.0]
        zoomDelta = defaultZoom

        let hw = Float(view.drawableSize.width) * defaultZoom
        let hh = Float(view.drawableSize.height) * defaultZoom
        camera.update(left: -hw, right: hw, bottom: -hh, top: hh)

        camera.orientation = defaultOrientation
        camera.position = defaultPosition

        onStartPublisher.send(self)
        onChangePublisher.send(self)
        onEndPublisher.send(self)
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
            let loaded = try JSONDecoder().decode(OrthographicCameraController.self, from: data)

            camera.setFrom(object: loaded.camera)

            defaultZoom = loaded.defaultZoom
            defaultPosition = loaded.defaultPosition
            defaultOrientation = loaded.defaultOrientation

            zoomDelta = loaded.zoomDelta
            panDelta = loaded.panDelta
            clearInputState()
        } catch {
            print(error.localizedDescription)
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        camera = try values.decode(OrthographicCamera.self, forKey: .camera)
        defaultPosition = try values.decode(simd_float3.self, forKey: .defaultPosition)
        defaultOrientation = try values.decode(simd_quatf.self, forKey: .defaultOrientation)
        defaultZoom = try values.decode(Float.self, forKey: .defaultZoom)
        zoomDelta = try values.decode(Float.self, forKey: .zoomDelta)
        panDelta = try values.decode(simd_float2.self, forKey: .panDelta)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(camera, forKey: .camera)
        try container.encode(defaultPosition, forKey: .defaultPosition)
        try container.encode(defaultOrientation, forKey: .defaultOrientation)
        try container.encode(defaultZoom, forKey: .defaultZoom)
        try container.encode(zoomDelta, forKey: .zoomDelta)
        try container.encode(panDelta, forKey: .panDelta)
    }

    private enum CodingKeys: String, CodingKey {
        case camera
        case defaultPosition
        case defaultOrientation
        case defaultZoom
        case zoomDelta
        case panDelta
    }

    // MARK: - Setup & Camera Transform Updates

    private func setup() {
        guard !isSetup, let view = view, view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }

        let hw = Float(view.drawableSize.width) * defaultZoom
        let hh = Float(view.drawableSize.height) * defaultZoom
        camera.update(left: -hw, right: hw, bottom: -hh, top: hh)

        isSetup = true
    }

    private func applyPan(_ deltaX: Float, _ deltaY: Float) {
        let cameraWidth = camera.right - camera.left
        let cameraHeight = camera.top - camera.bottom

        let deltaX = deltaX * cameraWidth
        let deltaY = deltaY * cameraHeight

        panDelta += [deltaX, deltaY]

        camera.position -= camera.worldRightDirection * deltaX
        camera.position += camera.worldUpDirection * deltaY

        onChangePublisher.send(self)
    }

    private func applyZoom(_ delta: Float) {
        let cameraWidth = camera.right - camera.left
        let cameraHeight = camera.top - camera.bottom

        let deltaX = delta * cameraWidth
        let deltaY = delta * cameraHeight

        camera.left -= deltaX
        camera.right += deltaX

        camera.top += deltaY
        camera.bottom -= deltaY

        onChangePublisher.send(self)
    }

    private func applyRoll(_ delta: Float) {
        camera.orientation *= simd_quatf(angle: delta, axis: camera.worldForwardDirection)
        onChangePublisher.send(self)
    }

    @discardableResult
    private func applyPendingInput(_ input: DrainedInput) -> Bool {
        var changed = false

        if input.pendingPan.x != 0.0 || input.pendingPan.y != 0.0 {
            applyPan(input.pendingPan.x, input.pendingPan.y)
            changed = true
        }

        if input.pendingZoom != 0.0 {
            applyZoom(input.pendingZoom)
            changed = true
        }

        if input.pendingRoll != 0.0 {
            applyRoll(input.pendingRoll)
            changed = true
        }

        return changed
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
                requestReset: state.requestReset,
                pendingPan: state.pendingPan,
                pendingZoom: state.pendingZoom,
                pendingRoll: state.pendingRoll
            )
            state.requestReset = false
            state.pendingPan = .zero
            state.pendingZoom = 0.0
            state.pendingRoll = 0.0
            return drained
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
                self?.mouseDown(with: event) ?? event
            }
        )

        otherMouseDraggedHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseDragged,
            handler: { [weak self] event in
                self?.mouseDragged(with: event) ?? event
            }
        )

        otherMouseUpHandler = NSEvent.addLocalMonitorForEvents(
            matching: .otherMouseUp,
            handler: { [weak self] event in
                self?.mouseUp(with: event) ?? event
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
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        panGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        panGestureRecognizer.minimumNumberOfTouches = 1
        panGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(panGestureRecognizer)

        rollGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(rollGesture))
        rollGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        view.addGestureRecognizer(rollGestureRecognizer)

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

    #if os(macOS)

    // MARK: - Mouse

    private func mouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerShouldBeginInteraction(event, view: view, onReject: { [weak self] in
            self?.setInteractionState(.inactive)
        }) else { return event }

        if event.clickCount == 2 {
            inputState.withState { state in
                state.requestReset = true
                state.interactionState = .inactive
            }
        } else {
            setInteractionState(.panning)
        }

        return event
    }

    private func mouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .panning }) else { return event }
        inputState.withState { state in
            state.pendingPan += [Float(event.deltaX / view.frame.size.width), Float(event.deltaY / view.frame.size.height)]
        }
        return event
    }

    private func mouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .panning }) else { return event }
        setInteractionState(.inactive)
        return event
    }

    // MARK: - Right Mouse

    private func rightMouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerShouldBeginInteraction(event, view: view, onReject: { [weak self] in
            self?.setInteractionState(.inactive)
        }) else { return event }
        setInteractionState(.zooming)
        return event
    }

    private func rightMouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .zooming }) else { return event }
        inputState.withState { state in
            state.pendingZoom += Float(-event.deltaY / view.frame.size.height)
        }
        return event
    }

    private func rightMouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window,
              inputState.withState({ $0.interactionState == .zooming }) else { return event }
        setInteractionState(.inactive)
        return event
    }

    // MARK: - Scroll Wheel

    private func scrollWheel(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerEventTargetsView(event, view: view) else { return event }

        if event.phase == .began {
            setInteractionState(.panning)
        }

        guard inputState.withState({ $0.interactionState == .panning }) else { return event }

        if event.phase == .changed {
            inputState.withState { state in
                state.pendingPan += [Float(event.scrollingDeltaX / view.frame.size.width), Float(event.scrollingDeltaY / view.frame.size.height)]
            }
        } else if event.phase == .ended {
            setInteractionState(.inactive)
        }

        return event
    }

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
                let delta = state.magnification - newMagnification
                state.pendingZoom += delta
                state.magnification = newMagnification
            }
        } else if gestureRecognizer.state == .ended {
            setInteractionState(.inactive)
        }
    }

    @objc private func rollGesture(_ gestureRecognizer: NSRotationGestureRecognizer) {
        if gestureRecognizer.state == .began { setInteractionState(.rolling) }

        guard inputState.withState({ $0.interactionState == .rolling }) else { return }

        if gestureRecognizer.state == .changed {
            inputState.withState { state in
                state.pendingRoll += -Float(gestureRecognizer.rotation)
            }
            gestureRecognizer.rotation = 0.0
        } else if gestureRecognizer.state == .ended {
            setInteractionState(.inactive)
        }
    }

    #else

    // MARK: - Gestures iOS

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
            setInteractionState(.rolling)
        }

        guard inputState.withState({ $0.interactionState == .rolling }) else { return }

        if gestureRecognizer.state == .changed {
            inputState.withState { state in
                state.pendingRoll += Float(gestureRecognizer.rotation)
            }
            gestureRecognizer.rotation = 0.0
        } else if gestureRecognizer.state == .ended {
            setInteractionState(.inactive)
        }
    }

    @objc private func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let view = view else { return }

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
                let deltaX = state.panCurrentPoint.x - state.panPreviousPoint.x
                let deltaY = state.panCurrentPoint.y - state.panPreviousPoint.y
                let dx = deltaX / Float(view.frame.size.width)
                let dy = deltaY / Float(view.frame.size.height)
                state.pendingPan += [dx, dy]
                state.panPreviousPoint = state.panCurrentPoint
            }
        } else if gestureRecognizer.state == .ended {
            setInteractionState(.inactive)
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
                state.pendingZoom += delta
                state.pinchScale = newScale
            }
        } else if gestureRecognizer.state == .ended {
            setInteractionState(.inactive)
        }
    }

    #endif

    internal func queuePanForTesting(_ pan: simd_float2) {
        inputState.withState { state in
            state.interactionState = .panning
            state.pendingPan += pan
        }
    }

    internal func queueZoomForTesting(_ zoom: Float) {
        inputState.withState { state in
            state.interactionState = .zooming
            state.pendingZoom += zoom
        }
    }

    internal func queueRollForTesting(_ roll: Float) {
        inputState.withState { state in
            state.interactionState = .rolling
            state.pendingRoll += roll
        }
    }
}
