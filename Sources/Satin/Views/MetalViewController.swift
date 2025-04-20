//
//  MetalViewController.swift
//  Satin
//
//  Created by Reza Ali on 1/21/24.
//

#if os(macOS)

import AppKit

public final class MetalViewController: NSViewController {
    public var renderer: any  MetalViewRendererDelegate
    public private(set) var metalView = MetalView()

    override public var acceptsFirstResponder: Bool { return true }
    override public func becomeFirstResponder() -> Bool { return true }
    override public func resignFirstResponder() -> Bool { return true }

    private var trackingArea: NSTrackingArea?

    // MARK: - Init

    public init(renderer: any MetalViewRendererDelegate) {
        
        print("MetalViewController NSViewController initializer renderer id: \(renderer.id)")

        self.renderer = renderer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init with Renderer")
    }

    // MARK: - Deinit

    deinit {
#if DEBUG_VIEWS
        print("\ndeinit - MetalViewController: \(renderer.id)\n")
#endif
        cleanup()
    }

    // MARK: - Load View

    override public func loadView() {
#if DEBUG_VIEWS
        print("loadView - MetalViewController: \(self.renderer.id)")
#endif
        view = self.metalView
    }

    // MARK: - View Did Load

    override public func viewDidLoad() {
        super.viewDidLoad()
#if DEBUG_VIEWS
        print("viewDidLoad - MetalViewController: \(self.renderer.id)")
#endif
        self.setupView()
        self.setupRenderer()

        self.setupEvents()
        self.setupTracking()
    }

    // MARK: - Setup View

    private func setupView() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
#if DEBUG_VIEWS
        print("setupView - MetalViewController: \(self.renderer.id)")
#endif
        self.metalView.metalLayer.device = device
    }

    // MARK: - Renderer

    private func setupRenderer() {
        guard let device = metalView.metalLayer.device, let queue = device.makeCommandQueue(), !renderer.isSetup else { return }
#if DEBUG_VIEWS
        print("setupRenderer - MetalViewController: \(self.renderer.id)")
#endif
        self.renderer.metalView = self.metalView
        self.renderer.device = device
        self.renderer.commandQueue = queue
        self.renderer.setup()
        self.renderer.isSetup = true
        self.renderer.appearance = self.getAppearance()

        self.metalView.metalLayer.pixelFormat = self.renderer.colorPixelFormat
        self.metalView.delegate = self.renderer
    }

    private func cleanupRenderer() {
        guard self.renderer.isSetup else { return }
#if DEBUG_VIEWS
        print("cleanupRenderer - MetalViewController: \(self.renderer.id)")
#endif
        self.renderer.cleanup()
        self.renderer.isSetup = false
    }

    // MARK: - Appearance

    private func getAppearance() -> MetalViewRenderer.Appearance {
        let name = self.metalView.effectiveAppearance.name
        if name == NSAppearance.Name.vibrantDark || name == NSAppearance.Name.darkAqua {
            return .dark
        }
        else {
            return .light
        }
    }

    // MARK: - Tracking

    private func setupTracking() {
#if DEBUG_VIEWS
        print("setupTracking - MetalViewController: \(self.renderer.id)")
#endif
        let area = NSTrackingArea(
            rect: self.view.bounds,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .inVisibleRect,
                .activeInKeyWindow
            ], owner: self, userInfo: nil
        )
        self.view.addTrackingArea(area)
        self.trackingArea = area
    }

    private func removeTracking() {
        guard let trackingArea = trackingArea else { return }
#if DEBUG_VIEWS
        print("removeTracking - MetalViewController: \(self.renderer.id)")
#endif
        self.view.removeTrackingArea(trackingArea)
        self.trackingArea = nil
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    // MARK: - Events

    private func setupEvents() {
#if DEBUG_VIEWS
        print("setupEvents - MetalViewController: \(self.renderer.id)")
#endif
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(self.updateAppearance),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.updateAppearance),
            name: Notification.Name("AppleInterfaceStyle"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.willTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc func willTerminate() {
#if DEBUG_VIEWS
        print("willTerminate - MetalViewController: \(self.renderer.id)")
#endif
        self.cleanup()
    }

    func cleanup() {
#if DEBUG_VIEWS
        print("cleanup - MetalViewController: \(self.renderer.id)")
#endif
        self.cleanupRenderer()
        self.removeEvents()
        self.removeTracking()
        self.removeEvents()
        self.metalView.delegate = nil
    }

    @objc func updateAppearance() {
        guard self.renderer.isSetup else { return }
        self.renderer.appearance = self.getAppearance()
    }

    private func removeEvents() {
#if DEBUG_VIEWS
        print("removeEvents - MetalViewController: \(self.renderer.id)")
#endif

        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
    }

    // MARK: - Events

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
#if DEBUG_VIEWS
        print("MetalViewController performKeyEquivalent: \(event.characters)")
#endif
        guard !self.renderer.performKeyEquivalent(with: event) else { return true }
        return super.performKeyEquivalent(with: event)
    }

    override public func keyDown(with event: NSEvent) {
#if DEBUG_VIEWS
        print("MetalViewController keyDown: \(event.characters)")
#endif
        guard !self.renderer.keyDown(with: event) else { return }
        super.keyDown(with: event)
    }

    override public func keyUp(with event: NSEvent) {
#if DEBUG_VIEWS
        print("MetalViewController keyUp: \(event.characters)")
#endif
        guard !self.renderer.keyUp(with: event) else { return }
        super.keyUp(with: event)
    }

    override public func flagsChanged(with event: NSEvent) {
#if DEBUG_VIEWS
        print("MetalViewController flagsChanged: \(event.modifierFlags)")
#endif
        guard !self.renderer.flagsChanged(with: event) else { return }
        super.flagsChanged(with: event)
    }

    override public func touchesBegan(with event: NSEvent) {
        self.renderer.touchesBegan(with: event)
    }

    override public func touchesEnded(with event: NSEvent) {
        self.renderer.touchesEnded(with: event)
    }

    override public func touchesMoved(with event: NSEvent) {
        self.renderer.touchesMoved(with: event)
    }

    override public func touchesCancelled(with event: NSEvent) {
        self.renderer.touchesCancelled(with: event)
    }

    override public func mouseMoved(with event: NSEvent) {
        self.renderer.mouseMoved(with: event)
    }

    override public func mouseDown(with event: NSEvent) {
        self.renderer.mouseDown(with: event)
    }

    override public func mouseDragged(with event: NSEvent) {
        self.renderer.mouseDragged(with: event)
    }

    override public func mouseUp(with event: NSEvent) {
        self.renderer.mouseUp(with: event)
    }

    override public func rightMouseDown(with event: NSEvent) {
        self.renderer.rightMouseDown(with: event)
    }

    override public func rightMouseDragged(with event: NSEvent) {
        self.renderer.rightMouseDragged(with: event)
    }

    override public func rightMouseUp(with event: NSEvent) {
        self.renderer.rightMouseUp(with: event)
    }

    override public func otherMouseDown(with event: NSEvent) {
        self.renderer.otherMouseDown(with: event)
    }

    override public func otherMouseDragged(with event: NSEvent) {
        self.renderer.otherMouseDragged(with: event)
    }

    override public func otherMouseUp(with event: NSEvent) {
        self.renderer.otherMouseUp(with: event)
    }

    override public func mouseEntered(with event: NSEvent) {
        self.renderer.mouseEntered(with: event)
    }

    override public func mouseExited(with event: NSEvent) {
        self.renderer.mouseExited(with: event)
    }

    override public func magnify(with event: NSEvent) {
        self.renderer.magnify(with: event)
    }

    override public func rotate(with event: NSEvent) {
        self.renderer.rotate(with: event)
    }

    override public func swipe(with event: NSEvent) {
        self.renderer.swipe(with: event)
    }

    override public func scrollWheel(with event: NSEvent) {
        self.renderer.scrollWheel(with: event)
    }
}

#elseif os(iOS) || os(tvOS) || os(visionOS)

import UIKit

public final class MetalViewController: UIViewController {
    public let renderer: MetalViewRenderer
    public private(set) var metalView = MetalView()

    override public var shouldAutorotate: Bool { return true }

    // MARK: - Init

    public init(renderer: MetalViewRenderer) {
        self.renderer = renderer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init with Renderer")
    }

    // MARK: - Deinit

    deinit {
#if DEBUG_VIEWS
        print("\ndeinit - MetalViewController: \(renderer.id)\n")
#endif
        cleanupRenderer()
        removeEvents()
        metalView.delegate = nil
    }

    // MARK: - Load View

    override public func loadView() {
#if DEBUG_VIEWS
        print("loadView - MetalViewController: \(self.renderer.id)")
#endif
        view = self.metalView
        view.isMultipleTouchEnabled = true
    }

    // MARK: - View Did Load

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.setupView()
        self.setupRenderer()
        self.setupEvents()
        self.setupAppearance()
    }

    override public var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    // MARK: - Setup View

    private func setupView() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
#if DEBUG_VIEWS
        print("setupView - MetalViewController: \(self.renderer.id)")
#endif
        self.metalView.metalLayer.device = device
    }

    // MARK: - Renderer

    private func setupRenderer() {
        guard let device = metalView.metalLayer.device, let queue = device.makeCommandQueue(), !renderer.isSetup
        else { return }
#if DEBUG_VIEWS
        print("setupRenderer - MetalViewController: \(self.renderer.id)")
#endif
        self.renderer.metalView = self.metalView
        self.renderer.device = device
        self.renderer.commandQueue = queue
        self.renderer.setup()
        self.renderer.isSetup = true
        self.renderer.appearance = self.getAppearance()

        self.metalView.metalLayer.pixelFormat = self.renderer.colorPixelFormat
        self.metalView.delegate = self.renderer
    }

    private func getAppearance() -> MetalViewRenderer.Appearance {
        if self.traitCollection.userInterfaceStyle == .dark {
            return .dark
        }
        else if self.traitCollection.userInterfaceStyle == .light {
            return .light
        }
        else if self.traitCollection.userInterfaceStyle == .unspecified {
            return .unspecified
        }
        else {
            return .unspecified
        }
    }

    private func cleanupRenderer() {
        guard self.renderer.isSetup else { return }
#if DEBUG_VIEWS
        print("cleanupRenderer - MetalViewController: \(self.renderer.id)")
#endif
        self.renderer.cleanup()
        self.renderer.isSetup = false
    }

    func setupAppearance() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self], handler: { (self: Self, previousTraitCollection: UITraitCollection) in
            guard self.renderer.isSetup,
                  previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle else { return }
            self.renderer.appearance = self.getAppearance()
        })
    }

    // MARK: - Events

    private func setupEvents() {
#if DEBUG_VIEWS
        print("setupEvents - MetalViewController: \(self.renderer.id)")
#endif
    }

    private func removeEvents() {
#if DEBUG_VIEWS
        print("removeEvents - MetalViewController: \(self.renderer.id)")
#endif
    }

    // MARK: - Events

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.renderer.touchesBegan(touches, with: event)
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.renderer.touchesMoved(touches, with: event)
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.renderer.touchesEnded(touches, with: event)
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.renderer.touchesCancelled(touches, with: event)
    }
}

#endif
