//
//  SliderView.swift
//  Slate macOS
//
//  Created by Reza Ali on 3/14/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Combine
import Satin

#if os(macOS)

import AppKit

final class SliderViewController: InputViewController, NSTextFieldDelegate {
    public weak var parameter: (any Parameter)? = nil
    var subscriptions = Set<AnyCancellable>()

    var inputField: NSTextField?
    var labelField: NSTextField?
    var slider: NSSlider?

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 52).isActive = true

        if let parameter = parameter {
            var value = 0.0
            var minValue = 0.0
            var maxValue = 1.0
            var stringValue = ""
            if let param = parameter as? FloatParameter {
                value = Double(param.value)
                minValue = Double(param.min)
                maxValue = Double(param.max)
                stringValue = String(format: "%.3f", value)

                param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                    guard let self = self, let slider = self.slider, let inputField = self.inputField else { return }
                    inputField.stringValue = String(format: "%.3f", newValue)
                    slider.doubleValue = Double(newValue)
                }.store(in: &subscriptions)

                param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                    guard let self = self, let slider = self.slider else { return }
                    slider.minValue = Double(newMinValue)
                }.store(in: &subscriptions)

                param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                    guard let self = self, let slider = self.slider else { return }
                    slider.maxValue = Double(newMaxValue)
                }.store(in: &subscriptions)
            }
            else if let param = parameter as? IntParameter {
                value = Double(param.value)
                minValue = Double(param.min)
                maxValue = Double(param.max)
                stringValue = "\(Int(value))"

                param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                    guard let self = self, let slider = self.slider, let inputField = self.inputField else { return }
                    inputField.stringValue = "\(newValue)"
                    slider.doubleValue = Double(newValue)
                }.store(in: &subscriptions)

                param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                    guard let self = self, let slider = self.slider else { return }
                    slider.minValue = Double(newMinValue)
                }.store(in: &subscriptions)

                param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                    guard let self = self, let slider = self.slider else { return }
                    slider.maxValue = Double(newMaxValue)
                }.store(in: &subscriptions)
            }
            else if let param = parameter as? DoubleParameter {
                value = param.value
                minValue = param.min
                maxValue = param.max
                stringValue = String(format: "%.3f", value)

                param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                    guard let self = self, let slider = self.slider, let inputField = self.inputField else { return }
                    inputField.stringValue = String(format: "%.3f", newValue)
                    slider.doubleValue = Double(newValue)
                }.store(in: &subscriptions)

                param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                    guard let self = self, let slider = self.slider else { return }
                    slider.minValue = newMinValue
                }.store(in: &subscriptions)

                param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                    guard let self = self, let slider = self.slider else { return }
                    slider.maxValue = newMaxValue
                }.store(in: &subscriptions)
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

            let slider = NSSlider(value: value, minValue: minValue, maxValue: maxValue, target: self, action: #selector(onSliderChange))
            slider.wantsLayer = true
            slider.translatesAutoresizingMaskIntoConstraints = false
            vStack.addView(slider, in: .center)
            slider.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: -16).isActive = true
            self.slider = slider

            let hStack = NSStackView()
            hStack.wantsLayer = true
            hStack.translatesAutoresizingMaskIntoConstraints = false
            hStack.orientation = .horizontal
            hStack.spacing = 0
            hStack.alignment = .centerY
            hStack.distribution = .gravityAreas
            vStack.addView(hStack, in: .center)
            hStack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: -14).isActive = true

            let labelField = NSTextField()
            labelField.font = .labelFont(ofSize: 12)
            labelField.translatesAutoresizingMaskIntoConstraints = false
            labelField.isEditable = false
            labelField.isSelectable = true
            labelField.isBordered = false
            labelField.backgroundColor = .clear
            labelField.stringValue = parameter.label + ":"
            hStack.addView(labelField, in: .leading)
            self.labelField = labelField

            let inputField = NSTextField()
            inputField.font = .boldSystemFont(ofSize: 11)
            inputField.stringValue = stringValue
            inputField.wantsLayer = true
            inputField.translatesAutoresizingMaskIntoConstraints = false
            inputField.stringValue = stringValue
            inputField.isEditable = true
            inputField.isSelectable = true
            inputField.isBordered = false
            inputField.backgroundColor = .clear
            inputField.delegate = self
            inputField.target = self
            inputField.action = #selector(onInputChanged)
            hStack.addView(inputField, in: .leading)
            self.inputField = inputField
        }
    }

    @objc func onSliderChange() {
        guard let slider = slider else { return }
        setValue(slider.doubleValue)
        deactivate()
    }

    func setValue(_ value: Double) {
        guard let parameter = parameter else { return }
        if let floatParam = parameter as? FloatParameter {
            floatParam.value = Float(value)
        }
        else if let doubleParam = parameter as? DoubleParameter {
            doubleParam.value = value
        }
        else if let intParam = parameter as? IntParameter {
            intParam.value = Int(value)
        }
    }

    @objc func onInputChanged(_ sender: NSTextField) {
        if let value = Double(sender.stringValue) {
            setValue(value)
            deactivateAsync()
        }
    }

    public func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            let charSet = NSCharacterSet(charactersIn: "-1234567890.").inverted
            let chars = textField.stringValue.components(separatedBy: charSet)
            textField.stringValue = chars.joined()
        }
    }

    deinit {}
}

#else

import UIKit

final class SliderViewController: WidgetViewController, UITextFieldDelegate {
    var subscriptions = Set<AnyCancellable>()

    override var minHeight: CGFloat {
        64
    }

    var slider: UISlider?
    var input: UITextField?

    var font: UIFont {
        .boldSystemFont(ofSize: 14)
    }

    override public func loadView() {
        setupView()
        setupVerticalStackView()
        setupSlider()
        setupHorizontalStackView()
        setupLabel()
        setupInput()
        setupBinding()
    }

    override func setupVerticalStackView() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fill
        view.addSubview(stack)
        stack.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stack.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        stack.heightAnchor.constraint(equalTo: view.heightAnchor, constant: -8).isActive = true
        stack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -16).isActive = true
        vStack = stack
    }

    override func setupHorizontalStackView() {
        guard let vStack = vStack else { return }
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.distribution = .fill
        vStack.addArrangedSubview(stack)
        stack.centerXAnchor.constraint(equalTo: vStack.centerXAnchor).isActive = true
        stack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: 0).isActive = true
        hStack = stack
    }

    func setupInput() {
        guard let hStack = hStack else { return }
        let input = UITextField()
        input.borderStyle = .none
        input.translatesAutoresizingMaskIntoConstraints = false
        input.font = font
        input.backgroundColor = .clear
        input.textAlignment = .right
        input.contentHuggingPriority(for: .horizontal)
        input.addAction(UIAction(handler: { [weak self] _ in
            guard let self, let input = self.input, let text = input.text, let value = Float(text) else { return }
            self.setValue(value)
        }), for: .editingChanged)
        hStack.addArrangedSubview(input)
        input.delegate = self
        self.input = input
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    } // return YES to allow editing to stop and to resign first responder status. NO to disallow the editing session to end

    func textFieldDidEndEditing(_ textField: UITextField) {
        if let input = input, let text = input.text, let value = Float(text) {
            setValue(value)
        }
        textField.resignFirstResponder()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard !string.isEmpty else {
            return true
        }

        if !CharacterSet(charactersIn: "-0123456789.").isSuperset(of: CharacterSet(charactersIn: string)) {
            return false
        }
        if string == ".", let text = textField.text, text.contains(".") {
            return false
        }

        // Allow text change
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func setupSlider() {
        guard let vStack = vStack else { return }
        let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 32, height: 32), primaryAction: UIAction(handler: { [unowned self] _ in
            if let slider = self.slider {
                self.setValue(slider.value)
            }
        }))
        slider.translatesAutoresizingMaskIntoConstraints = false
        vStack.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: 0).isActive = true
        self.slider = slider
    }

    override func setupBinding() {
        guard let parameter = parameter else { return }
        var value: Float = 0.0
        var minValue: Float = 0.0
        var maxValue: Float = 1.0
        var stringValue = ""

        if let param = parameter as? FloatParameter {
            value = param.value
            minValue = param.min
            maxValue = param.max
            stringValue = String(format: "%.3f", value)

            param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                guard let self = self, let slider = self.slider, let inputField = self.input else { return }
                inputField.text = String(format: "%.3f", newValue)
                slider.value = newValue
            }.store(in: &subscriptions)

            param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                guard let self = self, let slider = self.slider else { return }
                slider.minimumValue = newMinValue
            }.store(in: &subscriptions)

            param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                guard let self = self, let slider = self.slider else { return }
                slider.maximumValue = newMaxValue
            }.store(in: &subscriptions)
        }
        else if let param = parameter as? IntParameter {
            value = Float(param.value)
            minValue = Float(param.min)
            maxValue = Float(param.max)
            stringValue = "\(Int(value))"

            param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                guard let self = self, let slider = self.slider, let inputField = self.input else { return }
                inputField.text = "\(newValue)"
                slider.value = Float(newValue)
            }.store(in: &subscriptions)

            param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                guard let self = self, let slider = self.slider else { return }
                slider.minimumValue = Float(newMinValue)
            }.store(in: &subscriptions)

            param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                guard let self = self, let slider = self.slider else { return }
                slider.maximumValue = Float(newMaxValue)
            }.store(in: &subscriptions)
        }
        else if let param = parameter as? DoubleParameter {
            value = Float(param.value)
            minValue = Float(param.min)
            maxValue = Float(param.max)
            stringValue = String(format: "%.3f", value)

            param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                guard let self = self, let slider = self.slider, let inputField = self.input else { return }
                inputField.text = String(format: "%.3f", newValue)
                slider.value = Float(newValue)
            }.store(in: &subscriptions)

            param.minValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMinValue in
                guard let self = self, let slider = self.slider else { return }
                slider.minimumValue = Float(newMinValue)
            }.store(in: &subscriptions)

            param.maxValuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newMaxValue in
                guard let self = self, let slider = self.slider else { return }
                slider.maximumValue = Float(newMaxValue)
            }.store(in: &subscriptions)
        }

        if let slider = slider {
            slider.minimumValue = minValue
            slider.maximumValue = maxValue
            slider.value = value
        }

        if let label = label {
            label.text = "\(parameter.label)"
        }

        if let input = input {
            input.text = "\(stringValue)"
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
        slider = nil
    }
}

#endif
