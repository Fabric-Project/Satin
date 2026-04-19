//
//  CAMetalLayerHarnessView.swift
//  Example
//
//  Created by OpenAI on 4/19/26.
//

#if os(macOS)

import AppKit
import CoreVideo
import Metal
import QuartzCore
import SwiftUI

struct RawMetalLayerAView: View {
    var body: some View {
        RawMetalLayerAContainer()
            .ignoresSafeArea()
            .navigationTitle("Raw Metal A")
    }
}

struct RawMetalLayerBView: View {
    var body: some View {
        RawMetalLayerBContainer()
            .ignoresSafeArea()
            .navigationTitle("Raw Metal B")
    }
}

private struct RawMetalLayerAContainer: NSViewControllerRepresentable {
    func makeNSViewController(context: Self.Context) -> RawMetalLayerAViewController {
        RawMetalLayerAViewController()
    }

    func updateNSViewController(_ nsViewController: RawMetalLayerAViewController, context: Self.Context) {}
}

private struct RawMetalLayerBContainer: NSViewControllerRepresentable {
    func makeNSViewController(context: Self.Context) -> RawMetalLayerBViewController {
        RawMetalLayerBViewController()
    }

    func updateNSViewController(_ nsViewController: RawMetalLayerBViewController, context: Self.Context) {}
}

private final class RawMetalLayerAViewController: RawMetalLayerExampleViewController {
    init() {
        super.init(
            title: "Raw Metal A",
            clearColor: MTLClearColor(red: 0.82, green: 0.23, blue: 0.28, alpha: 1.0)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RawMetalLayerBViewController: RawMetalLayerExampleViewController {
    init() {
        super.init(
            title: "Raw Metal B",
            clearColor: MTLClearColor(red: 0.18, green: 0.36, blue: 0.82, alpha: 1.0)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class RawMetalLayerExampleViewController: NSViewController {
    private let layerView: RawMetalLayerView

    init(title: String, clearColor: MTLClearColor) {
        layerView = RawMetalLayerView(title: title, clearColor: clearColor)
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = layerView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        layerView.start()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        layerView.stop()
    }

    deinit {
        layerView.stop()
    }
}

private final class RawMetalLayerView: NSView {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let clearColor: MTLClearColor
    private let titleText: String

    private var frameIndex: UInt64 = 0
    private var displayLink: CVDisplayLink?

    private var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    init(title: String, clearColor: MTLClearColor) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            fatalError("Failed to create Metal device or command queue")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.clearColor = clearColor
        titleText = title

        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        configureMetalLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stop()
    }

    override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    func start() {
        guard displayLink == nil else { return }

        var newDisplayLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&newDisplayLink) == kCVReturnSuccess,
              let newDisplayLink
        else { return }

        CVDisplayLinkSetOutputHandler(newDisplayLink) { [weak self] _, _, _, _, _ in
            guard let self else { return kCVReturnSuccess }
            DispatchQueue.main.async {
                self.render()
            }
            return kCVReturnSuccess
        }

        displayLink = newDisplayLink
        CVDisplayLinkStart(newDisplayLink)
    }

    func stop() {
        guard let displayLink else { return }
        CVDisplayLinkStop(displayLink)
        self.displayLink = nil
    }

    private func configureMetalLayer() {
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 3
        metalLayer.isOpaque = true
        metalLayer.colorspace = nil
        layer?.name = titleText
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        guard size.width > 0.0, size.height > 0.0 else { return }

        metalLayer.drawableSize = size
    }

    private func render() {
        guard window != nil,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        frameIndex += 1

        let pulse = (sin(Double(frameIndex) * 0.03) + 1.0) * 0.05
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: min(clearColor.red + pulse, 1.0),
            green: min(clearColor.green + pulse, 1.0),
            blue: min(clearColor.blue + pulse, 1.0),
            alpha: clearColor.alpha
        )

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        encoder?.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

#if false
    #Preview {
        RawMetalLayerAView()
    }
#endif

#endif
