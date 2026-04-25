//
//  LightShadow.swift
//  Satin
//
//  Created by Reza Ali on 3/2/23.
//

import Combine
import Foundation
import Metal

public class Shadow {
    public var label: String
    public var texture: MTLTexture? = nil
    
    public var data: ShadowData {
        ShadowData(strength: strength, bias: bias, radius: radius)
    }

    public var camera: Camera
    public var resolution: (width: Int, height: Int) = (width:1024, height:1024)

    public var strength: Float = 1.0
    public var bias: Float = 0.00001
    public var radius: Float =  1.0

    public var texturePublisher = PassthroughSubject<Shadow, Never>()
    public var resolutionPublisher = PassthroughSubject<Shadow, Never>()
    public var dataPublisher = PassthroughSubject<Shadow, Never>()

    
    init(label: String) {
        self.label = label
        camera = OrthographicCamera(left: -5, right: 5, bottom: -5, top: 5, near: 0.01, far: 50.0)
    }
    
    public func update(light: Object) { fatalError("Subclasses must overload") }
    
    public func draw(context: Context, commandBuffer: MTLCommandBuffer, renderables: [Renderable]) {
        fatalError("Subclasses must overload")
    }

}
