//
//  DropDownViewController.swift
//  Slate
//
//  Created by Reza Ali on 3/24/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Combine
import Satin

#if os(macOS)

import AppKit

public final class DropDownViewController: NSViewController {
    public weak var parameter: StringParameter?
    var subscription: AnyCancellable?

    public var options: [String] = []
    var labelField: NSTextField!
    var dropDownMenu: NSPopUpButton!

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false

        if let parameter = parameter {
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
            hStack.orientation = .horizontal
            hStack.spacing = 4
            hStack.alignment = .centerY
            hStack.distribution = .gravityAreas
            vStack.addView(hStack, in: .center)
            hStack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: -14).isActive = true

            labelField = NSTextField()
            labelField.font = .labelFont(ofSize: 12)
            labelField.translatesAutoresizingMaskIntoConstraints = false
            labelField.isEditable = false
            labelField.isBordered = false
            labelField.backgroundColor = .clear
            labelField.stringValue = parameter.label
            hStack.addView(labelField, in: .leading)
            view.heightAnchor.constraint(equalTo: labelField.heightAnchor, constant: 16).isActive = true

            dropDownMenu = NSPopUpButton()
            dropDownMenu.wantsLayer = true
            dropDownMenu.translatesAutoresizingMaskIntoConstraints = false
            dropDownMenu.addItems(withTitles: options)
            dropDownMenu.selectItem(withTitle: parameter.value)
            dropDownMenu.target = self
            dropDownMenu.action = #selector(onSelected)
            dropDownMenu.bezelStyle = .texturedRounded
            hStack.addView(dropDownMenu, in: .trailing)

            subscription = parameter.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] value in
                guard let self,
                      let selectedItem = self.dropDownMenu.selectedItem,
                      selectedItem.title != value
                else { return }
                self.dropDownMenu.selectItem(withTitle: value)
            }
        }
    }

    @objc func onSelected(_ sender: NSPopUpButton) {
        guard let parameter = parameter, parameter.value != sender.title else { return }
        parameter.value = sender.title
    }

    deinit {}
}

#else

import UIKit

class DropDownViewController: WidgetViewController {
    var subscription: AnyCancellable?
    var button: UIButton?
    var options: [String] = []

    var font: UIFont {
        .boldSystemFont(ofSize: 14)
    }

    override open func loadView() {
        setupView()
        setupStackViews()
        setupLabel()
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

        button.setTitleColor(UIColor(named: "Text", in: Bundle(for: DropDownViewController.self), compatibleWith: nil), for: .normal)

        button.contentHorizontalAlignment = .trailing

        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8.0)
        configuration.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { [weak self] incoming in
                guard let self else { return incoming }
                var outgoing = incoming
                outgoing.font = font
                return outgoing
            }

        button.configuration = configuration

        button.layer.cornerRadius = 4
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(named: "Border", in: Bundle(for: DropDownViewController.self), compatibleWith: nil)?.cgColor
        button.showsMenuAsPrimaryAction = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        hStack.addArrangedSubview(button)
        self.button = button
    }

    override func setupBinding() {
        var stringValue = ""
        if let param = parameter as? StringParameter {
            stringValue = param.value
            subscription = param.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] value in
                guard let self else { return }
                self.setValue(value)
            }
        }

        if let button = button {
            button.setTitle(stringValue, for: .normal)
            var children: [UIAction] = []
            for option in options {
                children.append(UIAction(title: option, handler: {
                    [weak self] _ in self?.setValue(option)
                }))
            }
            let menu = UIMenu(title: "", options: .displayInline, children: children)
            button.menu = menu
        }

        if let label = label, let parameter = parameter {
            label.text = "\(parameter.label)"
        }
    }

    func setValue(_ value: String) {
        if let param = parameter as? StringParameter, param.value != value {
            param.value = value
        }
        if let button = button {
            button.setTitle(value, for: .normal)
        }
    }

    deinit {
        button = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if let button = button {
            button.layer.borderColor = UIColor(named: "Border", in: Bundle(for: DropDownViewController.self), compatibleWith: nil)?.cgColor
        }
    }
}

let testParam = StringParameter("Color", "Red", ["Red", "Green", "Blue"], .dropdown)
#Preview {
    let vc = DropDownViewController()
    vc.parameter = testParam
    return vc
}

#endif
