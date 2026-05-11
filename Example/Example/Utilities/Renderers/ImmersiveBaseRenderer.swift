//
//  ImmersiveBaseRenderer.swift
//  Example
//
//  Created by Reza Ali on 9/5/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

#if os(visionOS)

import Foundation
import Satin

class ImmersiveBaseRenderer: MetalLayerRenderer {
    var assetsURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Assets") }
    var sharedAssetsURL: URL { assetsURL.appendingPathComponent("Shared") }
    var rendererAssetsURL: URL { assetsURL.appendingPathComponent(String(describing: type(of: self))) }
    var dataURL: URL { rendererAssetsURL.appendingPathComponent("Data") }
    var pipelinesURL: URL { rendererAssetsURL.appendingPathComponent("Pipelines") }
    var texturesURL: URL { rendererAssetsURL.appendingPathComponent("Textures") }
    var modelsURL: URL { rendererAssetsURL.appendingPathComponent("Models") }

}

#endif
