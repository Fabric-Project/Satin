//
//  XYPadViewController.swift
//  Example
//
//  Created by Reza Ali on 8/9/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Combine
import Foundation

#if os(macOS)

import AppKit

final class XYPad: NSView {
    var onValueChanged: ((simd_float2) -> Void)?
    var value = simd_make_float2(0.0, 0.0) {
        didSet {
            guard !_settingValue else { return }
            valueNormalized = (value - minValue) / (maxValue - minValue)
        }
    }

    var minValue = simd_float2.zero {
        didSet {
            let newValueNormalized = (value - minValue) / (maxValue - minValue)
            if valueNormalized != newValueNormalized {
                valueNormalized = newValueNormalized
            }
        }
    }

    var maxValue = simd_float2.one {
        didSet {
            let newValueNormalized = (value - minValue) / (maxValue - minValue)
            if valueNormalized != newValueNormalized {
                valueNormalized = newValueNormalized
            }
        }
    }

    private var valueNormalized = simd_make_float2(0.5, 0.5) {
        didSet {
            needsDisplay = true
        }
    }

    private var _settingValue = false

    init(value: simd_float2, minValue: simd_float2, maxValue: simd_float2) {
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue

        self.valueNormalized = (value - minValue) / (maxValue - minValue)

        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawPad()
        drawGrid()
        drawKnob()
    }

    private func drawGrid() {
        // Set the color for the line
        NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setStroke()

        // Create a new NSBezierPath
        let xPath = NSBezierPath()
        xPath.lineWidth = 1.0
        xPath.move(to: NSPoint(x: 0, y: bounds.midY))
        xPath.line(to: NSPoint(x: bounds.width, y: bounds.midY))
        xPath.stroke()

        let yPath = NSBezierPath()
        yPath.lineWidth = 1.0
        yPath.move(to: NSPoint(x: bounds.midX, y: 0))
        yPath.line(to: NSPoint(x: bounds.midX, y: bounds.maxY))
        yPath.stroke()
    }

    private func drawPad() {
        let trackHeight: CGFloat = 16.0
        let trackRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.systemFill.withAlphaComponent(0.125).setFill()
        trackPath.fill()

        NSColor.tertiaryLabelColor.setStroke()
        trackPath.stroke()
    }

    private func drawKnob() {
        // Define the knob's properties
        let knobRadius: CGFloat = 8.0
        let knobX = CGFloat(valueNormalized.x) * (bounds.width - knobRadius * 2)
        let knobY = CGFloat(valueNormalized.y) * (bounds.height - knobRadius * 2)
        let knobRect = NSRect(x: knobX, y: knobY, width: knobRadius * 2, height: knobRadius * 2)

        if valueNormalized.x == 0.5 {
            NSColor.secondaryLabelColor.setStroke()
        }
        else {
            NSColor.tertiaryLabelColor.setStroke()
        }

        // Create a new NSBezierPath
        let xPath = NSBezierPath()
        xPath.lineWidth = 1.0
        xPath.move(to: NSPoint(x: knobX + knobRadius, y: 0))
        xPath.line(to: NSPoint(x: knobX + knobRadius, y: bounds.maxY))
        xPath.stroke()

        if valueNormalized.y == 0.5 {
            NSColor.secondaryLabelColor.setStroke()
        }
        else {
            NSColor.tertiaryLabelColor.setStroke()
        }

        let yPath = NSBezierPath()
        yPath.lineWidth = 1.0
        yPath.move(to: NSPoint(x: 0, y: knobY + 8))
        yPath.line(to: NSPoint(x: bounds.maxX, y: knobY + 8))
        yPath.stroke()

        // Draw the knob
        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSColor.labelColor.setFill()
        knobPath.fill()
    }

    override func mouseDown(with event: NSEvent) {
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(with: event)
    }

    private func updateValue(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        var x = min(max(location.x / bounds.width, 0), 1)
        var y = min(max(location.y / bounds.height, 0), 1)

        if abs(location.x - bounds.midX) < 2 {
            x = 0.5
        }

        if abs(location.y - bounds.midY) < 2 {
            y = 0.5
        }

        valueNormalized = simd_make_float2(Float(x), Float(y))
        setValue(simd_mix(minValue, maxValue, valueNormalized))
    }

    private func setValue(_ newValue: simd_float2) {
        _settingValue = true
        if value != newValue {
            value = newValue
            onValueChanged?(value)
        }
        _settingValue = false
    }
}

final class XYPadViewController: InputViewController {
    public weak var parameter: (any Parameter)? = nil
    var subscriptions = Set<AnyCancellable>()

    var labelField: NSTextField?
    var valueField: NSTextField?
    var pad: XYPad?

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        view.widthAnchor.constraint(equalToConstant: 240).isActive = true

        if let parameter = parameter {
            var value: simd_float2 = .zero
            var minValue: simd_float2 = .zero
            var maxValue: simd_float2 = .one
            var stringValue = ""

            if let param = parameter as? Float2Parameter {
                value = param.value
                minValue = param.min
                maxValue = param.max
                stringValue = String(format: "(%.3f, %.3f)", value.x, value.y)

                param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                    guard let self = self, let valueField = self.valueField, let pad = self.pad else { return }
                    valueField.stringValue = String(format: "(%.3f, %.3f)", newValue.x, newValue.y)
                    pad.value = newValue
                }.store(in: &subscriptions)

                param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                    guard let self = self, let pad = self.pad else { return }
                    pad.minValue = newMinValue
                }.store(in: &subscriptions)

                param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                    guard let self = self, let pad = self.pad else { return }
                    pad.maxValue = newMaxValue
                }.store(in: &subscriptions)
            }
            else if let param = parameter as? Int2Parameter {
                value = simd_make_float2(Float(param.value.x), Float(param.value.y))
                minValue = simd_make_float2(Float(param.min.x), Float(param.min.y))
                maxValue = simd_make_float2(Float(param.max.x), Float(param.max.y))
                stringValue = String(format: "(%.3f, %.3f)", value.x, value.y)

                param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                    guard let self = self, let valueField = self.valueField, let pad = self.pad else { return }
                    valueField.stringValue = String(format: "(%.3f, %.3f)", newValue.x, newValue.y)
                    pad.value = simd_make_float2(Float(newValue.x), Float(newValue.y))
                }.store(in: &subscriptions)

                param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                    guard let self = self, let pad = self.pad else { return }
                    pad.minValue = simd_make_float2(Float(newMinValue.x), Float(newMinValue.y))
                }.store(in: &subscriptions)

                param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                    guard let self = self, let pad = self.pad else { return }
                    pad.maxValue = simd_make_float2(Float(newMaxValue.x), Float(newMaxValue.y))
                }.store(in: &subscriptions)
            }

            let vStack = NSStackView()
            vStack.wantsLayer = true
            vStack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(vStack)
            vStack.orientation = .vertical
            vStack.distribution = .gravityAreas
            vStack.spacing = 8

            vStack.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            vStack.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            vStack.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
            vStack.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

            let pad = XYPad(value: value, minValue: minValue, maxValue: maxValue)
            pad.wantsLayer = true
            pad.layer?.isOpaque = false
            pad.layer?.backgroundColor = .clear
            pad.translatesAutoresizingMaskIntoConstraints = false
            pad.onValueChanged = { [weak self] value in
                guard let self, let valueField = self.valueField else { return }
                valueField.stringValue = String(format: "(%.3f, %.3f)", value.x, value.y)
                if let param = parameter as? Float2Parameter, param.value != value {
                    param.value = value
                }
                else if let param = parameter as? Int2Parameter {
                    let intValue = simd_make_int2(Int32(value.x), Int32(value.y))
                    if param.value != intValue {
                        param.value = intValue
                    }
                }
                self.deactivate()
            }
            vStack.addArrangedSubview(pad)
            pad.topAnchor.constraint(equalTo: vStack.topAnchor, constant: 8).isActive = true
            pad.heightAnchor.constraint(equalTo: vStack.widthAnchor, constant: -16).isActive = true
            pad.widthAnchor.constraint(equalTo: pad.heightAnchor).isActive = true

            self.pad = pad

            let hStack = NSStackView()
            hStack.wantsLayer = true
            hStack.translatesAutoresizingMaskIntoConstraints = false
            hStack.orientation = .horizontal
            hStack.spacing = 4
            hStack.alignment = .centerY
            hStack.distribution = .fillEqually
            vStack.addView(hStack, in: .trailing)
            hStack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: -16).isActive = true

            let labelField = NSTextField()
            labelField.wantsLayer = true
            labelField.font = .labelFont(ofSize: 12)
            labelField.translatesAutoresizingMaskIntoConstraints = false
            labelField.isEditable = false
            labelField.isSelectable = true
            labelField.isBordered = false
            labelField.backgroundColor = .clear
            labelField.stringValue = parameter.label
            hStack.addView(labelField, in: .leading)
            self.labelField = labelField

            let inputField = NSTextField()
            labelField.wantsLayer = true
            inputField.font = .boldSystemFont(ofSize: 11)
            inputField.wantsLayer = true
            inputField.translatesAutoresizingMaskIntoConstraints = false
            inputField.maximumNumberOfLines = 1
            inputField.alignment = .right
            inputField.stringValue = stringValue
            inputField.cell?.isBezeled = true
            inputField.bezelStyle = .roundedBezel
            inputField.drawsBackground = false
            inputField.isEditable = false
            inputField.isSelectable = true
            inputField.isBordered = false
            inputField.backgroundColor = .clear
            inputField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            hStack.addView(inputField, in: .trailing)
            valueField = inputField

            view.bottomAnchor.constraint(equalTo: hStack.bottomAnchor, constant: 8).isActive = true
        }
    }

    deinit {
        subscriptions.removeAll()
        pad = nil
        labelField = nil
        valueField = nil
    }
}

#else

import UIKit

final class XYPad: UIControl {
    var onValueChanged: ((simd_float2) -> Void)?
    var value = simd_make_float2(0.0, 0.0) {
        didSet {
            guard !_settingValue else { return }
            valueNormalized = (value - minValue) / (maxValue - minValue)
        }
    }

    var minValue = simd_float2.zero {
        didSet {
            let newValueNormalized = (value - minValue) / (maxValue - minValue)
            if valueNormalized != newValueNormalized {
                valueNormalized = newValueNormalized
            }
        }
    }

    var maxValue = simd_float2.one {
        didSet {
            let newValueNormalized = (value - minValue) / (maxValue - minValue)
            if valueNormalized != newValueNormalized {
                valueNormalized = newValueNormalized
            }
        }
    }

    private var valueNormalized = simd_make_float2(0.5, 0.5) {
        didSet {
            layoutSubviews()
        }
    }

    private var _settingValue = false

    private let padLayer = CALayer()
    private let xAxis = CALayer()
    private let yAxis = CALayer()

    private let thumbXAxis = CALayer()
    private let thumbYAxis = CALayer()
    private let thumbLayer = CALayer()

    init() {
        super.init(frame: .zero)
        setupLayers()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        // Setup track
        padLayer.backgroundColor = UIColor.systemFill.withAlphaComponent(0.125).cgColor
        padLayer.cornerRadius = 16
        padLayer.borderWidth = 1
        padLayer.borderColor = UIColor.tertiaryLabel.cgColor
        layer.addSublayer(padLayer)

        let axisColor = UIColor.tertiaryLabel.withAlphaComponent(0.5).cgColor
        xAxis.backgroundColor = axisColor
        layer.addSublayer(xAxis)

        yAxis.backgroundColor = axisColor
        layer.addSublayer(yAxis)

        let thumbAxisColor = UIColor.secondaryLabel.cgColor
        thumbXAxis.backgroundColor = thumbAxisColor
        layer.addSublayer(thumbXAxis)

        thumbYAxis.backgroundColor = thumbAxisColor
        layer.addSublayer(thumbYAxis)

        // Setup thumb
        thumbLayer.backgroundColor = UIColor.label.cgColor
        thumbLayer.cornerRadius = 14
        layer.addSublayer(thumbLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        padLayer.backgroundColor = UIColor.systemFill.withAlphaComponent(0.125).cgColor
        padLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height
        )

        // Layout Axis
        let axisColor = UIColor.tertiaryLabel.withAlphaComponent(0.5).cgColor

        xAxis.backgroundColor = axisColor
        xAxis.frame = CGRect(x: bounds.midX, y: 0, width: 1, height: bounds.height)

        yAxis.backgroundColor = axisColor
        yAxis.frame = CGRect(x: 0, y: bounds.midY, width: bounds.width, height: 1)

        let x = CGFloat(valueNormalized.x) * bounds.width
        let y = CGFloat(valueNormalized.y) * bounds.height

        if valueNormalized.x == 0.5 {
            thumbXAxis.backgroundColor = UIColor.secondaryLabel.cgColor
        }
        else {
            thumbXAxis.backgroundColor = UIColor.tertiaryLabel.cgColor
        }

        thumbXAxis.frame = CGRect(
            x: x,
            y: 0,
            width: 1,
            height: bounds.height
        )

        if valueNormalized.y == 0.5 {
            thumbYAxis.backgroundColor = UIColor.secondaryLabel.cgColor
        }
        else {
            thumbYAxis.backgroundColor = UIColor.tertiaryLabel.cgColor
        }

        thumbYAxis.frame = CGRect(
            x: 0,
            y: y,
            width: bounds.width,
            height: 1
        )

        // Layout thumb
        thumbLayer.backgroundColor = UIColor.label.cgColor
        let thumbSize: CGFloat = 28
        thumbLayer.frame = CGRect(
            x: x - thumbSize / 2,
            y: y - thumbSize / 2,
            width: thumbSize,
            height: thumbSize
        )
    }

    // Handle touch events to update slider value
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(with: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateValue(with: touch)
        return true
    }

    private func updateValue(with touch: UITouch) {
        let location = touch.location(in: self)

        var x = min(max(location.x / bounds.width, 0), 1)
        var y = min(max(location.y / bounds.height, 0), 1)

        if abs(location.x - bounds.midX) < 2 {
            x = 0.5
        }

        if abs(location.y - bounds.midY) < 2 {
            y = 0.5
        }

        valueNormalized = simd_make_float2(Float(x), Float(y))
        setValue(simd_mix(minValue, maxValue, valueNormalized))
    }

    private func setValue(_ newValue: simd_float2) {
        _settingValue = true
        if value != newValue {
            value = newValue
            onValueChanged?(value)
        }
        _settingValue = false
    }
}

import UIKit

final class XYPadViewController: WidgetViewController {
    var subscriptions = Set<AnyCancellable>()

    var pad: XYPad?
    var valueLabel: UILabel?

    var font: UIFont {
        .boldSystemFont(ofSize: 14)
    }

    override public func loadView() {
        setupView()
        setupVerticalStackView()
        setupPad()
        setupHorizontalStackView()
        setupLabel()
        setupValueLabel()
        setupBinding()
    }

    override func setupVerticalStackView() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        stack.distribution = .fill
        view.addSubview(stack)

        stack.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stack.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        stack.heightAnchor.constraint(equalTo: view.heightAnchor, constant: -16).isActive = true
        stack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -16).isActive = true
        vStack = stack
    }

    override func setupHorizontalStackView() {
        guard let vStack = vStack else { return }
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 0
        stack.alignment = .fill
        stack.distribution = .fill
        vStack.addArrangedSubview(stack)
        stack.centerXAnchor.constraint(equalTo: vStack.centerXAnchor).isActive = true
        stack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: 0).isActive = true
        stack.heightAnchor.constraint(equalToConstant: 24).isActive = true
        hStack = stack
    }

    func setupPad() {
        guard let vStack = vStack else { return }
        let pad = XYPad()
        pad.translatesAutoresizingMaskIntoConstraints = false
        vStack.addArrangedSubview(pad)
        pad.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
        pad.heightAnchor.constraint(equalTo: pad.widthAnchor).isActive = true

        pad.onValueChanged = { [weak self] value in
            guard let self, let valueLabel = self.valueLabel else { return }
            valueLabel.text = String(format: "(%.3f, %.3f)", value.x, value.y)
            if let param = parameter as? Float2Parameter, param.value != value {
                param.value = value
            }
            else if let param = parameter as? Int2Parameter {
                let intValue = simd_make_int2(Int32(value.x), Int32(value.y))
                if param.value != intValue {
                    param.value = intValue
                }
            }
        }

        self.pad = pad
    }

    func setupValueLabel() {
        guard let hStack = hStack else { return }
        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.numberOfLines = 0
        valueLabel.lineBreakMode = NSLineBreakMode.byWordWrapping
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        valueLabel.font = font
        valueLabel.text = ""
        hStack.addArrangedSubview(valueLabel)
        self.valueLabel = valueLabel
    }

    override func setupBinding() {
        guard let parameter = parameter else { return }

        var value: simd_float2 = .zero
        var minValue: simd_float2 = .zero
        var maxValue: simd_float2 = .one
        var stringValue = ""

        if let param = parameter as? Float2Parameter {
            value = param.value
            minValue = param.min
            maxValue = param.max
            stringValue = String(format: "(%.3f, %.3f)", value.x, value.y)

            param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                guard let self = self, let valueLabel = self.valueLabel, let pad = self.pad else { return }
                valueLabel.text = String(format: "(%.3f, %.3f)", newValue.x, newValue.y)
                pad.value = newValue
            }.store(in: &subscriptions)

            param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                guard let self = self, let pad = self.pad else { return }
                pad.minValue = newMinValue
            }.store(in: &subscriptions)

            param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                guard let self = self, let pad = self.pad else { return }
                pad.maxValue = newMaxValue
            }.store(in: &subscriptions)
        }
        else if let param = parameter as? Int2Parameter {
            value = simd_make_float2(Float(param.value.x), Float(param.value.y))
            minValue = simd_make_float2(Float(param.min.x), Float(param.min.y))
            maxValue = simd_make_float2(Float(param.max.x), Float(param.max.y))
            stringValue = String(format: "(%.3f, %.3f)", value.x, value.y)

            param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                guard let self = self, let valueLabel = self.valueLabel, let pad = self.pad else { return }
                valueLabel.text = String(format: "(%.3f, %.3f)", newValue.x, newValue.y)
                pad.value = simd_make_float2(Float(newValue.x), Float(newValue.y))
            }.store(in: &subscriptions)

            param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                guard let self = self, let pad = self.pad else { return }
                pad.minValue = simd_make_float2(Float(newMinValue.x), Float(newMinValue.y))
            }.store(in: &subscriptions)

            param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                guard let self = self, let pad = self.pad else { return }
                pad.maxValue = simd_make_float2(Float(newMaxValue.x), Float(newMaxValue.y))
            }.store(in: &subscriptions)
        }

        if let pad {
            pad.minValue = minValue
            pad.maxValue = maxValue
            pad.value = value
        }

        if let label {
            label.text = "\(parameter.label)"
        }

        if let valueLabel {
            valueLabel.text = "\(stringValue)"
        }
    }

    func setValue(_ value: Float) {
        if let parameter = parameter {
            if parameter is FloatParameter {
                let floatParam = parameter as! FloatParameter
                floatParam.value = value
            }
            else if parameter is DoubleParameter {
                let doubleParam = parameter as! DoubleParameter
                doubleParam.value = Double(value)
            }
            else if parameter is IntParameter {
                let intParam = parameter as! IntParameter
                intParam.value = Int(value)
            }
        }
    }

    deinit {
        pad = nil
    }
}

#endif
