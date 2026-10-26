//
//  CameraController.swift
//  Satin
//
//  Created by Reza Ali on 03/25/23.
//

import Combine
import Foundation

#if os(macOS)
import AppKit
#endif

public enum CameraControllerState {
    case panning // moves the camera either up to right
    case rotating // rotates the camera around an arcball
    case dollying // moves the camera forward
    case zooming // moves the camera closer to target
    case rolling // rotates the camera around its forward axis
    case tweening // tweening
    case inactive
}

public protocol CameraController {
    var isEnabled: Bool { get }

    var view: MetalView? { get set }

    var state: CameraControllerState { get }

    func update(frame: FrameTime)
    func enable()
    func disable()
    func reset()
    func resize(_ size: (width: Float, height: Float))

    func save(url: URL)
    func load(url: URL)
}

#if os(macOS)
func cameraControllerEventTargetsView(_ event: NSEvent, view: MetalView) -> Bool {
    guard let window = event.window, window == view.window else { return false }

    let point = view.convert(event.locationInWindow, from: nil)
    guard view.bounds.contains(point) else { return false }

    let insets = view.safeAreaInsets
    let safeAreaBounds = NSRect(
        x: view.bounds.minX + insets.left,
        y: view.bounds.minY + insets.bottom,
        width: max(0.0, view.bounds.width - insets.left - insets.right),
        height: max(0.0, view.bounds.height - insets.top - insets.bottom)
    )

    return safeAreaBounds.contains(point)
}

func cameraControllerShouldBeginInteraction(_ event: NSEvent, view: MetalView, onReject: () -> Void) -> Bool {
    guard let window = event.window, window == view.window else { return false }
    guard cameraControllerEventTargetsView(event, view: view) else {
        onReject()
        return false
    }
    return true
}
#endif

/// A damped tween's step over `deltaTime`, played out as if updated once a frame at 60 Hz, where
/// each frame multiplies the velocity by `damping` and then moves by it. `remaining` is the
/// velocity left afterwards and `travelled` how far it moved meanwhile, both as multiples of the
/// starting velocity, so a tween covers the same ground in the same time at any frame rate.
func dampedTweenStep(damping: Float, deltaTime: TimeInterval) -> (remaining: Float, travelled: Float) {
    let framesAt60Hz = Float(deltaTime * 60)
    let remaining = pow(damping, framesAt60Hz)
    let travelled = damping == 1 ? framesAt60Hz : damping * (1 - remaining) / (1 - damping)
    return (remaining, travelled)
}
