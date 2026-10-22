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

    private var defaultPosition = simd_make_float3(0.0, 0.0, 1.0)
    private var defaultOrientation = simd_quaternion(matrix_identity_float4x4)

    private var defaultZoom: Float = 0.5
    private var zoomDelta: Float = 0.5
    private var panDelta: simd_float2 = .zero
    private var panCurrentPoint: simd_float2 = .zero
    private var panPreviousPoint: simd_float2 = .zero

    /// What the event handlers saw, for `update(frame:)` to apply where the camera is owned. Pans
    /// and zooms are fractions of the view's size.
    enum Input {
        case begin(CameraControllerState)
        case pan(simd_float2)
        case zoom(Float)
        case roll(Float)
        case end
        case reset
    }

    let inputQueue = CameraControllerInputQueue<Input>()
    private var takenInputs = ContiguousArray<Input>()

    /// The gesture the event handlers are following. Main thread only; `state` is the camera side.
    private var gesture: CameraControllerState = .inactive

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
    private var magnifyGestureRecognizer: NSMagnificationGestureRecognizer!
    private var rollGestureRecognizer: NSRotationGestureRecognizer!

    #else

    private var rollRotation: Float = 0.0
    private var rollGestureRecognizer: UIRotationGestureRecognizer!

    private var panGestureRecognizer: UIPanGestureRecognizer!

    private var rotateGestureRecognizer: UIPanGestureRecognizer!

    private var pinchScale: Float = 1.0
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

    public func update(frame: FrameTime) {
        setup()
        applyInput()
    }

    /// Applies what the event handlers queued since the last update, in order.
    private func applyInput() {
        takenInputs.removeAll(keepingCapacity: true)
        inputQueue.take(into: &takenInputs)
        for input in takenInputs {
            switch input {
                case let .begin(newState):
                    state = newState
                case let .pan(delta):
                    guard state == .panning else { continue }
                    pan(delta.x, delta.y)
                case let .zoom(amount):
                    guard state == .zooming else { continue }
                    zoom(amount)
                case let .roll(amount):
                    guard state == .rolling else { continue }
                    roll(amount)
                case .end:
                    state = .inactive
                case .reset:
                    reset()
            }
        }
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
        // Gestures seen before disabling never reach the camera.
        inputQueue.discardPending()
        gesture = .inactive

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
        guard let view = view else { return }

        state = .inactive

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

    private func pan(_ deltaX: Float, _ deltaY: Float) {
        let cameraWidth = camera.right - camera.left
        let cameraHeight = camera.top - camera.bottom

        let deltaX = deltaX * cameraWidth
        let deltaY = deltaY * cameraHeight

        panDelta += [deltaX, deltaY]

        camera.position -= camera.worldRightDirection * deltaX
        camera.position += camera.worldUpDirection * deltaY

        onChangePublisher.send(self)
    }

    private func zoom(_ delta: Float) {
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

    private func roll(_ delta: Float) {
        camera.orientation *= simd_quatf(angle: delta, axis: camera.worldForwardDirection)
        onChangePublisher.send(self)
    }

    // MARK: - Events

    private func enableEvents() {
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

    private func disableEvents() {
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

    // MARK: - Gestures (main thread)

    private func begin(_ newGesture: CameraControllerState) {
        gesture = newGesture
        inputQueue.append(.begin(newGesture))
    }

    private func end() {
        gesture = .inactive
        inputQueue.append(.end)
    }

    #if os(macOS)

    // MARK: - Mouse

    private func mouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerShouldBeginInteraction(event, view: view, onReject: { [weak self] in
            self?.end()
        }) else { return event }

        if event.clickCount == 2 {
            gesture = .inactive
            inputQueue.append(.reset)
        } else {
            begin(.panning)
        }

        return event
    }

    private func mouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, gesture == .panning else { return event }
        inputQueue.append(.pan(simd_make_float2(Float(event.deltaX / view.frame.size.width), Float(event.deltaY / view.frame.size.height))))
        return event
    }

    private func mouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, gesture == .panning else { return event }
        end()
        return event
    }

    // MARK: - Right Mouse

    private func rightMouseDown(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerShouldBeginInteraction(event, view: view, onReject: { [weak self] in
            self?.end()
        }) else { return event }
        begin(.zooming)
        return event
    }

    private func rightMouseDragged(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, gesture == .zooming else { return event }
        inputQueue.append(.zoom(Float(-event.deltaY / view.frame.size.height)))
        return event
    }

    private func rightMouseUp(with event: NSEvent) -> NSEvent? {
        guard let view = view, event.window == view.window, gesture == .zooming else { return event }
        end()
        return event
    }

    // MARK: - Scroll Wheel

    private func scrollWheel(with event: NSEvent) -> NSEvent? {
        guard let view = view, cameraControllerEventTargetsView(event, view: view) else { return event }

        if event.phase == .began {
            begin(.panning)
        }

        guard gesture == .panning else { return event }

        if event.phase == .changed {
            inputQueue.append(.pan(simd_make_float2(Float(event.scrollingDeltaX / view.frame.size.width),
                                                    Float(event.scrollingDeltaY / view.frame.size.height))))
        } else if event.phase == .ended {
            end()
        }

        return event
    }

    @objc private func magnifyGesture(_ gestureRecognizer: NSMagnificationGestureRecognizer) {
        let newMagnification = Float(gestureRecognizer.magnification)
        if gestureRecognizer.state == .began {
            begin(.zooming)
            magnification = newMagnification
        }

        guard gesture == .zooming else { return }

        if gestureRecognizer.state == .changed {
            inputQueue.append(.zoom(magnification - newMagnification))
            magnification = newMagnification
        } else if gestureRecognizer.state == .ended {
            end()
        }
    }

    @objc private func rollGesture(_ gestureRecognizer: NSRotationGestureRecognizer) {
        if gestureRecognizer.state == .began { begin(.rolling) }

        guard gesture == .rolling else { return }

        if gestureRecognizer.state == .changed {
            inputQueue.append(.roll(-Float(gestureRecognizer.rotation)))
            gestureRecognizer.rotation = 0.0
        } else if gestureRecognizer.state == .ended {
            end()
        }
    }

    #else

    // MARK: - Gestures iOS

    @objc private func tapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer.state == .ended {
            gesture = .inactive
            inputQueue.append(.reset)
        }
    }

    @objc private func rollGesture(_ gestureRecognizer: UIRotationGestureRecognizer) {
        if gestureRecognizer.state == .began {
            begin(.rolling)
        }

        guard gesture == .rolling else { return }

        if gestureRecognizer.state == .changed {
            inputQueue.append(.roll(Float(gestureRecognizer.rotation)))
            gestureRecognizer.rotation = 0.0
        } else if gestureRecognizer.state == .ended {
            end()
        }
    }

    @objc private func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let view = view else { return }

        if gestureRecognizer.state == .began {
            begin(.panning)
            let translation = gestureRecognizer.translation(in: view)
            panPreviousPoint = simd_make_float2(Float(translation.x), Float(translation.y))
        }

        guard gesture == .panning else { return }

        if gestureRecognizer.state == .changed {
            let translation = gestureRecognizer.translation(in: view)
            panCurrentPoint = simd_make_float2(Float(translation.x), Float(translation.y))

            let deltaX = panCurrentPoint.x - panPreviousPoint.x
            let deltaY = panCurrentPoint.y - panPreviousPoint.y

            let dx = deltaX / Float(view.frame.size.width)
            let dy = deltaY / Float(view.frame.size.height)

            inputQueue.append(.pan(simd_make_float2(dx, dy)))
            panPreviousPoint = panCurrentPoint
        } else if gestureRecognizer.state == .ended {
            end()
        }
    }

    @objc private func pinchGesture(_ gestureRecognizer: UIPinchGestureRecognizer) {
        if gestureRecognizer.state == .began {
            begin(.zooming)
            pinchScale = Float(gestureRecognizer.scale)
        }

        guard gesture == .zooming else { return }

        if gestureRecognizer.state == .changed {
            let newScale = Float(gestureRecognizer.scale)
            inputQueue.append(.zoom(pinchScale - newScale))
            pinchScale = newScale
        } else if gestureRecognizer.state == .ended {
            end()
        }
    }

    #endif
}
