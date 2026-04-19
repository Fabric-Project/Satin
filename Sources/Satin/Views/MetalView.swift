//
//  MetalView.swift
//  Satin
//
//  Created by Reza Ali on 1/21/24.
//

#if os(macOS)

import AppKit
import Foundation
import QuartzCore

public protocol DragDelegate: AnyObject {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation
    func draggingEnded(_ sender: NSDraggingInfo)
    func draggingExited(_ sender: NSDraggingInfo?)
    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool
    func concludeDragOperation(_ sender: NSDraggingInfo?)
}

public protocol TouchDelegate: AnyObject {
    func touchesBegan(with event: NSEvent)
    func touchesMoved(with event: NSEvent)
    func touchesEnded(with event: NSEvent)
    func touchesCancelled(with event: NSEvent)
}

public final class MetalView: NSView, CALayerDelegate {
    public weak var dragDelegate: DragDelegate?
    public weak var touchDelegate: TouchDelegate?

    public var isPaused: Bool {
        get {
            _displayLinkPaused
        }
        set {
#if DEBUG_VIEW
            print("isPaused - MetalView: \(newValue)")
#endif
            if newValue {
                pauseRenderLoop()
            }
            else {
                resumeRenderLoop()
            }
        }
    }

    public var drawableSize: CGSize { metalLayer.drawableSize }

    weak var delegate: MetalViewRendererDelegate?

    public private(set) lazy var metalLayer: CAMetalLayer = self.layer as! CAMetalLayer

    public var contentScaleFactor: CGFloat { window?.screen?.backingScaleFactor ?? 1 }

    override public var acceptsFirstResponder: Bool { return true }

    private var _displayLinkPaused = false
    private var _displayLink: CVDisplayLink?
    private var _displaySource: DispatchSourceUserDataAdd?
    private let _dispatchRenderLoop: CVDisplayLinkOutputCallback = {
        _, _, _, _, _, displayLinkContext in
        let source = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(displayLinkContext!).takeUnretainedValue()
        source.add(data: 1)
        return kCVReturnSuccess
    }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // MARK: - Deinit

    deinit {
#if DEBUG_VIEW
        print("\ndeinit - MetalView: \(delegate?.id)\n")
#endif
    }

    // MARK: - Layer

    override public func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    // MARK: - Configure

    private func configure() {
#if DEBUG_VIEW
        print("\n\n\nconfigure - MetalView: \(delegate?.id)")
#endif
        allowedTouchTypes = [.indirect, .direct]
        wantsRestingTouches = false

        autoresizingMask = [.width, .height]

        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        metalLayer.maximumDrawableCount = maxBuffersInFlight
        metalLayer.delegate = self

        metalLayer.colorspace = nil // CGColorSpace(name: CGColorSpace.extendedSRGB)
        metalLayer.wantsExtendedDynamicRangeContent = true
    }

    // MARK: - View Window Change

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let window = window {
#if DEBUG_VIEW
            print("viewDidMoveToWindow - MetalView: \(delegate?.id), \(window)")
#endif
            setupRenderLoop(screen: window.screen)
            resizeDrawable()
        }
        else {
#if DEBUG_VIEW
            print("viewDidMoveToWindow - MetalView: \(delegate?.id) - NO WINDOW")
            stopRenderLoop()
#endif
        }
    }

    override public func viewDidHide() {
        super.viewDidHide()
#if DEBUG_VIEW
        print("viewDidHide - MetalView: \(delegate?.id)")
#endif
    }

    override public func viewDidUnhide() {
        super.viewDidUnhide()
#if DEBUG_VIEW
        print("viewDidUnhide - MetalView: \(delegate?.id)")
#endif
    }

    // MARK: - Layer Rendering

    private func render() {
        guard let delegate, let drawable = metalLayer.nextDrawable() else { return }
        delegate.draw(metalLayer: metalLayer, drawable: drawable)
    }

    // MARK: - Event Based Rendering

    public func display(_ layer: CALayer) {
        render()
    }

    public func draw(_ layer: CALayer, in ctx: CGContext) {
        render()
    }

    override public func draw(_ dirtyRect: NSRect) {
        render()
    }

    // MARK: - Appearance

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
#if DEBUG_VIEW
        print("viewDidChangeEffectiveAppearance - MetalView: \(effectiveAppearance.name)")
#endif
        if let metalViewController = nextResponder as? MetalViewController {
            metalViewController.updateAppearance()
        }

        render()
    }

    // MARK: - Render Loop

    func setupRenderLoop(screen: NSScreen?) {
        guard _displayLink == nil else { return }

#if DEBUG_VIEW
        print("setupRenderLoop - MetalView: \(delegate?.id)")
#endif
        _displaySource = DispatchSource.makeUserDataAddSource(queue: DispatchQueue.main)
        _displaySource!.setEventHandler { [weak self] in
            self?.render()
        }
        _displaySource!.resume()

        var cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink)

        assert(cvReturn == kCVReturnSuccess)

        cvReturn = CVDisplayLinkSetOutputCallback(
            _displayLink!,
            _dispatchRenderLoop,
            Unmanaged.passUnretained(_displaySource!).toOpaque()
        )

        assert(cvReturn == kCVReturnSuccess)

        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID

        cvReturn = CVDisplayLinkSetCurrentCGDisplay(_displayLink!, displayID ?? CGMainDisplayID())

        assert(cvReturn == kCVReturnSuccess)

        if !_displayLinkPaused {
            CVDisplayLinkStart(_displayLink!)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    func pauseRenderLoop() {
        if let displayLink = _displayLink, !_displayLinkPaused {
#if DEBUG_VIEW
            print("pauseRenderLoop - MetalView: \(delegate?.id)")
#endif
            CVDisplayLinkStop(displayLink)
        }

        _displayLinkPaused = true
    }

    func resumeRenderLoop() {
        if let displayLink = _displayLink, _displayLinkPaused {
#if DEBUG_VIEW
            print("resumeRenderLoop - MetalView: \(delegate?.id)")
#endif
            CVDisplayLinkStart(displayLink)
        }

        _displayLinkPaused = false
    }

    func stopRenderLoop() {
        guard _displayLink != nil else { return }
#if DEBUG_VIEW
        print("stopRenderLoop - MetalView: \(delegate?.id)")
#endif
        pauseRenderLoop()

        _displayLink = nil
        _displaySource?.cancel()
        _displaySource = nil
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === window else { return }
#if DEBUG_VIEW
        print("windowWillClose - MetalView: \(delegate?.id)")
#endif
        stopRenderLoop()
    }

    // MARK: - Resize

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resizeDrawable()
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeDrawable()
    }

    override public func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        resizeDrawable()
    }

    private func resizeDrawable() {
        let newScaleFactor = contentScaleFactor
        var newSize = bounds.size

        newSize.width *= newScaleFactor
        newSize.height *= newScaleFactor

        guard newSize.width > 0, newSize.height > 0 else { return }

        guard newSize.height != metalLayer.drawableSize.height ||
            newSize.width != metalLayer.drawableSize.width else { return }
#if DEBUG_VIEW
        print("resizeDrawable - MetalView: \(delegate?.id)")
#endif
        metalLayer.drawableSize = newSize

        delegate?.drawableResized(size: newSize, scaleFactor: newScaleFactor)
    }

    // MARK: - Drag & Drop

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let dd = dragDelegate {
            return dd.draggingEntered(sender)
        }
        return []
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let dd = dragDelegate {
            return dd.draggingUpdated(sender)
        }
        return []
    }

    override public func draggingEnded(_ sender: NSDraggingInfo) {
        dragDelegate?.draggingEnded(sender)
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        dragDelegate?.draggingExited(sender)
    }

    override public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let dd = dragDelegate {
            return dd.prepareForDragOperation(sender)
        }
        return false
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let dd = dragDelegate {
            return dd.performDragOperation(sender)
        }
        return false
    }

    override public func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dragDelegate?.concludeDragOperation(sender)
    }

    // MARK: - Mouse

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Touches

    override public func touchesBegan(with event: NSEvent) {
        touchDelegate?.touchesBegan(with: event)
    }

    override public func touchesMoved(with event: NSEvent) {
        touchDelegate?.touchesMoved(with: event)
    }

    override public func touchesEnded(with event: NSEvent) {
        touchDelegate?.touchesEnded(with: event)
    }

    override public func touchesCancelled(with event: NSEvent) {
        touchDelegate?.touchesCancelled(with: event)
    }
}

#elseif os(iOS) || os(tvOS) || os(visionOS)

import Foundation
import QuartzCore
import UIKit

public final class MetalView: UIView {
    public var isPaused: Bool {
        get {
            _displayLinkPaused
        }
        set {
#if DEBUG_VIEW
            print("set(isPaused) - MetalView: \(delegate?.id) - isPaused: \(newValue)")
#endif
            if newValue {
                pauseRenderLoop()
            }
            else {
                resumeRenderLoop()
            }
        }
    }

    public var drawableSize: CGSize {
        metalLayer.drawableSize
    }

    public var preferredFramesPerSecond: Int = 120 {
        didSet {
            if #available(iOS 15.0, *) {
                _displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: Float(preferredFramesPerSecond))
            }
            else {
                _displayLink?.preferredFramesPerSecond = preferredFramesPerSecond
            }
        }
    }

    weak var delegate: MetalViewRendererDelegate?

    public private(set) lazy var metalLayer: CAMetalLayer = self.layer as! CAMetalLayer

    private var _displayLinkPaused = false
    private var _displayLink: CADisplayLink?

    // MARK: - Init

    override public init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // MARK: - Deinit

    deinit {
#if DEBUG_VIEW
        print("\ndeinit - MetalView: \(delegate?.id)\n")
#endif
        NotificationCenter.default.removeObserver(self)

        stopRenderLoop()
    }

    // MARK: - Layer

    override public class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    // MARK: - Configure

    private func configure() {
#if DEBUG_VIEW
        print("configure - MetalView: \(delegate?.id)")
#endif
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        metalLayer.maximumDrawableCount = maxBuffersInFlight
        metalLayer.delegate = self
    }

    // MARK: - View Window Change

    override public func didMoveToWindow() {
        super.didMoveToWindow()
#if DEBUG_VIEW
        print("didMoveToWindow - MetalView: \(delegate?.id), - window: \(window)")
#endif
        if window != nil {
            setupRenderLoop()
            resizeDrawable()
        }
        else {
            stopRenderLoop()
        }
    }

    // MARK: - Render Loop

    private func setupRenderLoop() {
#if DEBUG_VIEW
        print("setupRenderLoop - MetalView: \(delegate?.id)")
#endif
        _displayLink?.isPaused = true
        _displayLink?.invalidate()
        _displayLink = nil

        let displayLink = CADisplayLink(target: self, selector: #selector(render))
        displayLink.isPaused = _displayLinkPaused
        displayLink.preferredFramesPerSecond = preferredFramesPerSecond
        displayLink.add(to: .main, forMode: .default)

        _displayLink = displayLink

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground(_:)),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground(_:)),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc func didEnterBackground(_ notification: Notification) {
#if DEBUG_VIEW
        print("didEnterBackground - MetalView: \(delegate?.id)")
#endif
        _displayLink?.isPaused = true
    }

    @objc func willResignActive(_ notification: Notification) {
#if DEBUG_VIEW
        print("willResignActive - MetalView: \(delegate?.id)")
#endif
        _displayLink?.isPaused = true
    }

    @objc func willEnterForeground(_ notification: Notification) {
#if DEBUG_VIEW
        print("willEnterForeground - MetalView: \(delegate?.id)")
#endif
        _displayLink?.isPaused = _displayLinkPaused
    }

    private func stopRenderLoop() {
        guard _displayLink != nil else { return }
#if DEBUG_VIEW
        print("stopRenderLoop - MetalView: \(delegate?.id)")
#endif
        _displayLink?.isPaused = true
        _displayLink?.remove(from: .main, forMode: .default)
        _displayLink?.invalidate()
        _displayLink = nil
    }

    private func pauseRenderLoop() {
#if DEBUG_VIEW
        print("pauseRenderLoop - MetalView: \(delegate?.id)")
#endif
        _displayLinkPaused = true
        _displayLink?.isPaused = true
    }

    private func resumeRenderLoop() {
#if DEBUG_VIEW
        print("resumeRenderLoop - MetalView: \(delegate?.id)")
#endif
        _displayLinkPaused = false
        _displayLink?.isPaused = false
    }

    // MARK: - Render

    @objc private func render() {
        guard let drawable = metalLayer.nextDrawable() else { return }
        delegate?.draw(metalLayer: metalLayer, drawable: drawable)
    }

    // MARK: - Event Based Rendering

    override public func display(_ layer: CALayer) {
        render()
    }

    override public func draw(_ layer: CALayer, in ctx: CGContext) {
        render()
    }

    override public func draw(_ rect: CGRect) {
        render()
    }

    // MARK: - Resize

    override public func layoutSubviews() {
        super.layoutSubviews()
        resizeDrawable()
    }

    override public var bounds: CGRect {
        get {
            super.bounds
        }
        set {
            super.bounds = newValue
            resizeDrawable()
        }
    }

    override public var frame: CGRect {
        get {
            super.frame
        }
        set {
            super.frame = newValue
            resizeDrawable()
        }
    }

    override public var contentScaleFactor: CGFloat {
        get {
            super.contentScaleFactor
        }
        set {
            super.contentScaleFactor = newValue
            resizeDrawable()
        }
    }

    private func resizeDrawable() {
        let newScaleFactor = contentScaleFactor
        var newSize = bounds.size

        newSize.width *= newScaleFactor
        newSize.height *= newScaleFactor

        guard newSize.width > 0, newSize.height > 0 else { return }

        guard newSize.height != metalLayer.drawableSize.height ||
            newSize.width != metalLayer.drawableSize.width else { return }
#if DEBUG_VIEW
        print("resizeDrawable - MetalView: \(delegate?.id)")
#endif
        metalLayer.drawableSize = newSize

        delegate?.drawableResized(size: newSize, scaleFactor: newScaleFactor)
    }
}

#endif
