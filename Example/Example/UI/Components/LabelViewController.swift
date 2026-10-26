//
//  LabelViewController.swift
//  Slate macOS
//
//  Created by Reza Ali on 3/14/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Combine
import Satin

#if os(macOS)

import AppKit

final class LabelViewController: NSViewController, NSTextFieldDelegate {
    public weak var parameter: StringParameter?
    var subscription: AnyCancellable?

    var labelField: NSTextField!
    var labelValue: NSTextField!
    var viewHeightConstraint: NSLayoutConstraint!
    var viewWidthConstraint: NSLayoutConstraint!

    override func loadView() {
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
            vStack.addView(hStack, in: .center)
            hStack.orientation = .horizontal
            hStack.alignment = .top
            hStack.distribution = .gravityAreas
            hStack.spacing = 0

            hStack.widthAnchor.constraint(equalTo: vStack.widthAnchor, constant: -16).isActive = true

            labelField = NSTextField()
            labelField.font = .labelFont(ofSize: 12)
            labelField.wantsLayer = true
            labelField.isEditable = false
            labelField.isBordered = false
            labelField.maximumNumberOfLines = 100
            labelField.backgroundColor = .clear
            labelField.stringValue = parameter.label + ": "
            hStack.addView(labelField, in: .leading)

            labelValue = NSTextField()
            labelValue.font = .boldSystemFont(ofSize: 11)
            labelValue.wantsLayer = true
            labelValue.isEditable = false
            labelValue.isBordered = false
            labelValue.isSelectable = true
            labelValue.maximumNumberOfLines = 100
            labelValue.backgroundColor = .clear
            labelValue.stringValue = parameter.value
            labelValue.alignment = .right
            hStack.addView(labelValue, in: .trailing)

            viewHeightConstraint = view.heightAnchor.constraint(equalTo: labelValue.heightAnchor, constant: 16)
            viewHeightConstraint.isActive = true

            viewWidthConstraint = view.widthAnchor.constraint(equalToConstant: 240)
            viewWidthConstraint.isActive = false

            subscription = parameter.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
                guard let self, self.labelValue.stringValue != newValue else { return }
                self.labelValue.stringValue = newValue
                self.labelValue.layout()
                self.view.needsLayout = true
            }
        }
    }

    override func viewWillLayout() {
        let w = labelValue.intrinsicContentSize.width
        if w < 240 {
            viewWidthConstraint.isActive = true
        }
        else {
            viewWidthConstraint.isActive = false
        }
    }

    deinit {}
}

#else

import UIKit

final class LabelViewController: WidgetViewController {
    var subscription: AnyCancellable?
    var valueLabel: UILabel?

    var font: UIFont {
        .boldSystemFont(ofSize: 14)
    }

    override func loadView() {
        setupView()
        setupStackViews()
        setupLabel()
        setupValueLabel()
        setupBinding()
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

    func setupValueLabel() {
        guard let hStack = hStack else { return }
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.text = "Label"
        label.textAlignment = .right
        label.isUserInteractionEnabled = true
        hStack.addArrangedSubview(label)
        valueLabel = label
    }

    override func setupBinding() {
        guard let parameter = parameter as? StringParameter else { return }

        subscription = parameter.valuePublisher.receive(on: DispatchQueue.main).sink { [weak self] newValue in
            guard let self, let valueLabel, valueLabel.text != newValue else { return }
            valueLabel.text = newValue
        }

        if let label = label {
            label.text = "\(parameter.label):"
        }

        if let value = valueLabel {
            value.text = "\(parameter.value)"
        }
    }
}

#endif
