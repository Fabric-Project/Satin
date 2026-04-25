//
//  BaseRenderer.swift
//  Example
//
//  Created by Reza Ali on 3/22/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Foundation
import Metal
import Satin

#if canImport(AppKit)
import AppKit
#endif

class BaseRenderer: MetalViewRenderer {
    // MARK: - Paths

    var assetsURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Assets") }
    var sharedAssetsURL: URL { assetsURL.appendingPathComponent("Shared") }
    var rendererAssetsURL: URL { assetsURL.appendingPathComponent(String(describing: type(of: self))) }
    var dataURL: URL { rendererAssetsURL.appendingPathComponent("Data") }
    var pipelinesURL: URL { rendererAssetsURL.appendingPathComponent("Pipelines") }
    var texturesURL: URL { rendererAssetsURL.appendingPathComponent("Textures") }
    var modelsURL: URL { rendererAssetsURL.appendingPathComponent("Models") }

    // MARK: - Parameters

    var inspectorWindow: InspectorWindow?

    var paramKeys: [String] {
        return []
    }

    var params: [String: ParameterGroup?] {
        return [:]
    }

    override func setup() {
        setupInspector()
    }

#if os(macOS)

    func openEditor() {
        if let editorUrl = UserDefaults.standard.url(forKey: "Editor") {
            NSWorkspace.shared.open([assetsURL], withApplicationAt: editorUrl, configuration: .init(), completionHandler: nil)
        }
        else {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.allowsMultipleSelection = false
            openPanel.canCreateDirectories = false
            openPanel.begin { [unowned self] (result: NSApplication.ModalResponse) in
                if result == .OK {
                    if let editorUrl = openPanel.url {
                        UserDefaults.standard.set(editorUrl, forKey: "Editor")
                        self.openEditor()
                    }
                }
                openPanel.close()
            }
        }
    }

    override func keyDown(with event: NSEvent) -> Bool {
        if event.characters == "c" {
            if event.modifierFlags.contains(.command) {
                UserDefaults.standard.setValue(nil, forKey: "Editor")
            }
            openEditor()
            return true
        }
        else if event.characters == "p" {
            if inspectorWindow == nil {
                setupInspector()
            }
            else {
                toggleInspector()
            }
            return true
        }
        return false
    }
#endif

    override func cleanup() {
        super.cleanup()
#if os(macOS)
        inspectorWindow?.close()
#endif
    }

    func setupInspector() {
        var panelOpenStates: [String: Bool] = [:]
        if let inspectorWindow = inspectorWindow, let inspector = inspectorWindow.inspectorViewController {
            let panels = inspector.getPanels()
            for panel in panels {
                if let label = panel.title {
                    panelOpenStates[label] = panel.open
                }
            }
        }

        if inspectorWindow == nil {
#if os(macOS)
            let inspectorWindow = InspectorWindow("Inspector")
            inspectorWindow.setIsVisible(true)
#else
            let inspectorWindow = InspectorWindow("Inspector", edge: .right)
            metalView.addSubview(inspectorWindow.view)
#endif
            self.inspectorWindow = inspectorWindow
        }

        if let inspectorWindow = inspectorWindow, let inspectorViewController = inspectorWindow.inspectorViewController {
            if inspectorViewController.getPanels().count > 0 {
                inspectorViewController.removeAllPanels()
            }

            updateUI(inspectorViewController)

            let panels = inspectorViewController.getPanels()
            for panel in panels {
                if let label = panel.title {
                    if let open = panelOpenStates[label] {
                        panel.open = open
                    }
                }
            }
        }
    }

    func updateUI(_ inspectorViewController: InspectorViewController) {
        let paramters = params
        for key in paramKeys {
            if let param = paramters[key], let p = param {
                let panel = ParameterGroupViewController(key, parameters: p)
                inspectorViewController.addPanel(panel)
            }
        }
    }

#if os(macOS)
    public func toggleInspector() {
        if let inspectorWindow = inspectorWindow {
            inspectorWindow.setIsVisible(!inspectorWindow.isVisible)
        }
    }
#endif
}
