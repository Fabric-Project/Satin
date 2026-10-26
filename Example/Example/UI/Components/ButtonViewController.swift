//
//  ButtonViewController.swift
//  Youi
//
//  Created by Reza Ali on 2/8/21.
//

import Combine
import Satin

#if os(macOS)

import AppKit

public final class ButtonViewController: NSViewController {
    public weak var parameter: BoolParameter?
    var subscription: AnyCancellable?

    var button: NSButton!
    var defaultState: Bool!

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false

        if let parameter = parameter {
            defaultState = parameter.value

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
            hStack.spacing = 0

            hStack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: -16).isActive = true

            button = NSButton()
            button.wantsLayer = true
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .rounded

            button.title = parameter.label
            button.translatesAutoresizingMaskIntoConstraints = false
            hStack.addView(button, in: .leading)
            button.widthAnchor.constraint(equalTo: hStack.widthAnchor).isActive = true
            button.state = (parameter.value ? .on : .off)
            button.target = self
            button.action = #selector(ButtonViewController.onButtonChange)

            view.heightAnchor.constraint(equalTo: button.heightAnchor, constant: 16).isActive = true

            subscription = parameter.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] value in
                let newState: NSControl.StateValue = (value ? .on : .off)
                guard let self, self.button.state != newState else { return }
                self.button.state = newState
            }
        }
    }

    @objc func onButtonChange() {
        let newValue = button.state == .on
        guard let parameter, parameter.value != newValue else { return }

        parameter.value = newValue

        guard defaultState != parameter.value else { return }
        parameter.value = defaultState
    }

    deinit {
        subscription = nil
    }
}

#else

import UIKit

final class ButtonViewController: WidgetViewController {
    var button: UIButton?

    override public func loadView() {
        setupView()
        setupStackViews()
        setupButton()
        setupBinding()
    }

    override func setupHorizontalStackView() {
        guard let vStack = vStack else { return }
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .fillProportionally
        vStack.addArrangedSubview(stack)
        stack.centerXAnchor.constraint(equalTo: vStack.centerXAnchor).isActive = true
        stack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: 0).isActive = true
        hStack = stack
    }

    func setupButton() {
        guard let hStack = hStack else { return }
        let button = UIButton(type: .roundedRect)
        button.setTitleColor(UIColor(named: "Text", in: Bundle(for: ButtonViewController.self), compatibleWith: nil), for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 14)
        button.layer.cornerRadius = 4
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(named: "Border", in: Bundle(for: ButtonViewController.self), compatibleWith: nil)?.cgColor
        button.addAction(UIAction(handler: { [weak self] _ in
            guard let self, let parameter = self.parameter as? BoolParameter else { return }
            parameter.value.toggle()
        }), for: .touchUpInside)

        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        hStack.addArrangedSubview(button)
        self.button = button
    }

    override func setupBinding() {
        var stringValue = ""
        if let param = parameter as? BoolParameter, let button = button {
            stringValue = param.label
            button.setTitle(stringValue, for: .normal)
        }
    }

    deinit {
        button = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if let button = button {
            button.layer.borderColor = UIColor(named: "Border", in: Bundle(for: ButtonViewController.self), compatibleWith: nil)?.cgColor
        }
    }
}

#endif
