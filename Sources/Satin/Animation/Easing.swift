//
//  Easing.swift
//  Juicer
//
//  Created by Reza Ali on 7/24/20.
//

import Foundation

public enum Easing: CaseIterable {
    case linear
    case smoothstep
    case smootherstep
    case inSine
    case outSine
    case inOutSine
    case inQuad
    case outQuad
    case inOutQuad
    case inCubic
    case outCubic
    case inOutCubic
    case inQuart
    case outQuart
    case inOutQuart
    case inQuint
    case outQuint
    case inOutQuint
    case inExpo
    case outExpo
    case inOutExpo
    case inCirc
    case outCirc
    case inOutCirc
    case inBack
    case outBack
    case inOutBack
    case inElastic
    case outElastic
    case inOutElastic
    case inBounce
    case outBounce
    case inOutBounce
    
    public func title() -> String {
        switch self
        {
        case .linear:
            return "Linear"
        case .smoothstep:
            return  "Smoothstep"
        case .smootherstep:
            return "Smootherstep"
        case .inSine:
            return "In Sine"
        case .outSine:
            return "Out Sine"
        case .inOutSine:
            return "Sine"
        case .inQuad:
            return "In Quad"
        case .outQuad:
            return "Out Quad"
        case .inOutQuad:
            return "Quad"
        case .inCubic:
            return "In Cubic"
        case .outCubic:
            return "Out Cubic"
        case .inOutCubic:
            return "Cubic"
        case .inQuart:
            return "In Quart"
        case .outQuart:
            return "Out Quart"
        case .inOutQuart:
            return "Quart"
        case .inQuint:
            return "In Quint"
        case .outQuint:
            return "Out Quint"
        case .inOutQuint:
            return "Quint"
        case .inExpo:
            return "In Expo"
        case .outExpo:
            return "Out Expo"
        case .inOutExpo:
            return "Expo"
        case .inCirc:
            return "In Circ"
        case .outCirc:
            return "Out Circ"
        case .inOutCirc:
            return "Circ"
        case .inBack:
            return "In Back"
        case .outBack:
            return "Out Back"
        case .inOutBack:
            return "Back"
        case .inElastic:
            return "In Elastic"
        case .outElastic:
            return "Out Elastic"
        case .inOutElastic:
            return "Elastic"
        case .inBounce:
            return "In Bounce"
        case .outBounce:
            return "Out Bounce"
        case .inOutBounce:
            return "Bounce"
            
        }
    }

    public var function: (Double) -> Double {
        switch self {
            case .linear:
                easeLinear
            case .smoothstep:
                easeSmoothstep
            case .smootherstep:
                easeSmootherstep
            case .inSine:
                easeInSine
            case .outSine:
                easeOutSine
            case .inOutSine:
                easeInOutSine
            case .inQuad:
                easeInQuad
            case .outQuad:
                easeOutQuad
            case .inOutQuad:
                easeInOutQuad
            case .inCubic:
                easeInCubic
            case .outCubic:
                easeOutCubic
            case .inOutCubic:
                easeInOutCubic
            case .inQuart:
                easeInQuart
            case .outQuart:
                easeOutQuart
            case .inOutQuart:
                easeInOutQuart
            case .inQuint:
                easeInQuint
            case .outQuint:
                easeOutQuint
            case .inOutQuint:
                easeInOutQuint
            case .inExpo:
                easeInExpo
            case .outExpo:
                easeOutExpo
            case .inOutExpo:
                easeInOutExpo
            case .inCirc:
                easeInCirc
            case .outCirc:
                easeOutCirc
            case .inOutCirc:
                easeInOutCirc
            case .inBack:
                easeInBack
            case .outBack:
                easeOutBack
            case .inOutBack:
                easeInOutBack
            case .inElastic:
                easeInElastic
            case .outElastic:
                easeOutElastic
            case .inOutElastic:
                easeInOutElastic
            case .inBounce:
                easeInBounce
            case .outBounce:
                easeOutBounce
            case .inOutBounce:
                easeInOutBounce
        }
    }
}
