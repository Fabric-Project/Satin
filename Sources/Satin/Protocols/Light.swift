//
//  Light.swift
//
//
//  Created by Reza Ali on 11/2/22.
//

import Combine
import Foundation
import simd

public protocol Light: AnyObject {
    var type: LightType { get }

    var data: LightData { get }

    var color: simd_float3 { get set } // color
    var intensity: Float { get set }

    var castShadow: Bool { get }
    var shadow: Shadow { get }

    var publisher: PassthroughSubject<Light, Never> { get }
}
