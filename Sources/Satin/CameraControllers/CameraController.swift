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

    func update()
    func enable()
    func disable()
    func reset()
    func resize(_ size: (width: Float, height: Float))

    func save(url: URL)
    func load(url: URL)
}

func cameraControllerPerformUIWork(_ work: () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.sync(execute: work)
    }
}

final class ControllerInputMailbox<State> {
    private let lock = UnfairLock()
    private var state: State

    init(_ state: State) {
        self.state = state
    }

    func withState<R>(_ work: (inout State) -> R) -> R {
        lock.sync {
            work(&state)
        }
    }
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
