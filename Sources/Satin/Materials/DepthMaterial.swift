//
//  DepthMaterial.swift
//  Satin
//
//  Created by Reza Ali on 6/24/20.
//

import Metal

public final class DepthMaterial: Material {
    public var color: Bool {
        get {
            get("Color", as: BoolParameter.self)!.value
        }
        set {
            set("Color", newValue)
        }
    }

    public var invert: Bool {
        get {
            get("Invert", as: BoolParameter.self)!.value
        }
        set {
            set("Invert", newValue)
        }
    }

    public var near: Float {
        get {
            get("Near", as: FloatParameter.self)!.value
        }
        set {
            set("Near", newValue)
        }
    }

    public var far: Float {
        get {
            get("Far", as: FloatParameter.self)!.value
        }
        set {
            set("Far", newValue)
        }
    }

    public init(color: Bool = true, invert: Bool = false, camera: Camera? = nil) {
        super.init()
        set("Color", color)
        set("Invert", invert)
        if let camera = camera {
            set("Near", camera.near)
            set("Far", camera.far)
        } else {
            set("Near", -1.0)
            set("Far", -1.0)
        }
    }

    public required init() {
        super.init()
        set("Color", true)
        set("Invert", false)
        set("Near", -1.0)
        set("Far", -1.0)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
