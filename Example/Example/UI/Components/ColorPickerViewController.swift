//
//  SliderView.swift
//  Slate macOS
//
//  Created by Reza Ali on 3/14/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Combine
import simd

import Satin

#if os(macOS)

import AppKit

public final class ColorPickerViewController: NSViewController {
    public weak var parameter: (any Parameter)? = nil
    var subscription: AnyCancellable?

    var labelField: NSTextField?
    var colorWell: NSColorWell?

    var hasAlpha: Bool {
        return parameter is Float4Parameter
    }

    override public func loadView() {
        NSColorPanel.shared.showsAlpha = true

        view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 40).isActive = true

        guard let parameter = parameter else { return }

        var value: simd_float4 = .one

        if let param = parameter as? Float4Parameter {
            subscription = param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] value in
                guard let self = self, let colorWell = self.colorWell else { return }
                colorWell.color = NSColor(
                    deviceRed: CGFloat(value.x),
                    green: CGFloat(value.y),
                    blue: CGFloat(value.z),
                    alpha: CGFloat(value.w)
                )
            }
            value = param.value
        }
        else if let param = parameter as? Float3Parameter {
            subscription = param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] value in
                guard let self = self, let colorWell = self.colorWell else { return }
                colorWell.color = NSColor(
                    deviceRed: CGFloat(value.x),
                    green: CGFloat(value.y),
                    blue: CGFloat(value.z),
                    alpha: 1.0
                )
            }
            value = simd_make_float4(param.value, 1.0)
        }

        let vStack = NSStackView()
        vStack.wantsLayer = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vStack)
        vStack.orientation = .vertical
        vStack.distribution = .gravityAreas
        vStack.spacing = 4

        vStack.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        vStack.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        vStack.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        vStack.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

        let hStack = NSStackView()
        hStack.wantsLayer = true
        hStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.addView(hStack, in: .center)
        hStack.orientation = .horizontal
        hStack.alignment = .centerY
        hStack.distribution = .gravityAreas
        hStack.spacing = 4
        hStack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: -16).isActive = true

        let colorWell = NSColorWell()
        colorWell.wantsLayer = true

        colorWell.color = NSColor(deviceRed: CGFloat(value.x), green: CGFloat(value.y), blue: CGFloat(value.z), alpha: CGFloat(value.w))

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 24).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        colorWell.target = self
        colorWell.action = #selector(ColorPickerViewController.onColorChange)
        hStack.addView(colorWell, in: .leading)
        self.colorWell = colorWell

        let labelField = NSTextField()
        labelField.font = .labelFont(ofSize: 12)
        labelField.wantsLayer = true
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.isEditable = false
        labelField.isBordered = false
        labelField.backgroundColor = .clear
        labelField.stringValue = parameter.label
        hStack.addView(labelField, in: .leading)
        self.labelField = labelField
    }

    @objc func onColorChange(_ sender: NSColorWell) {
        if let parameter = parameter, let color = sender.color.usingColorSpace(.deviceRGB) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            if let param = parameter as? Float4Parameter {
                param.value = simd_make_float4(Float(red), Float(green), Float(blue), Float(alpha))
            }
            else if let param = parameter as? Float3Parameter {
                param.value = simd_make_float3(Float(red), Float(green), Float(blue))
            }
        }
    }
}

#else

import UIKit

final class ColorPickerViewController: WidgetViewController {
    var subscription: AnyCancellable?
    var colorWell: UIColorWell?

    override var minHeight: CGFloat {
        56
    }

    override func loadView() {
        setupView()
        setupStackViews()
        setupColorWell()
        setupLabel()
        setupBinding()
    }

    override func setupHorizontalStackView() {
        super.setupHorizontalStackView()
        if let stack = hStack {
            stack.spacing = 8
            stack.distribution = .fill
            stack.alignment = .center
        }
    }

    func setupColorWell() {
        guard let stack = hStack else { return }
        let colorWell = UIColorWell()
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.addAction(UIAction(handler: { [weak self] _ in
            guard let self, let well = self.colorWell, let color = well.selectedColor else { return }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            if let param = self.parameter as? Float4Parameter {
                param.value = simd_make_float4(Float(red), Float(green), Float(blue), Float(alpha))
            }
            else if let param = self.parameter as? Float3Parameter {
                param.value = simd_make_float3(Float(red), Float(green), Float(blue))
            }

        }), for: .valueChanged)
        stack.addArrangedSubview(colorWell)
        self.colorWell = colorWell
    }

    override func setupBinding() {
        if let param = parameter as? Float4Parameter {
            subscription = param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] value in
                guard let self = self, let colorWell = self.colorWell else { return }
                colorWell.selectedColor = UIColor(
                    red: CGFloat(value.x),
                    green: CGFloat(value.y),
                    blue: CGFloat(value.z),
                    alpha: CGFloat(value.w)
                )
            }

            if let colorWell = colorWell {
                let value = param.value
                colorWell.selectedColor = UIColor(
                    red: CGFloat(value.x),
                    green: CGFloat(value.y),
                    blue: CGFloat(value.z),
                    alpha: CGFloat(value.w)
                )
            }
        }
        else if let param = parameter as? Float3Parameter {
            subscription = param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] value in
                guard let self = self, let colorWell = self.colorWell else { return }
                colorWell.selectedColor = UIColor(
                    red: CGFloat(value.x),
                    green: CGFloat(value.y),
                    blue: CGFloat(value.z),
                    alpha: CGFloat(1.0)
                )
            }

            if let colorWell = colorWell {
                let value = param.value
                colorWell.selectedColor = UIColor(
                    red: CGFloat(value.x),
                    green: CGFloat(value.y),
                    blue: CGFloat(value.z),
                    alpha: CGFloat(1.0)
                )
            }
        }

        super.setupBinding()
    }

    deinit {
        colorWell = nil
    }
}

#endif
