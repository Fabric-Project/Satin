import Combine
import QuartzCore
import simd

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class Tweener: Sendable {
    private nonisolated(unsafe) static var tweens: [Tween] = []

    /// Advances every tween to `frame.time`, once per frame, and drops the ones that complete.
    public class func update(frame: FrameTime) {
        for i in stride(from: tweens.count - 1, through: 0, by: -1) {
            if tweens[i].update(time: frame.time) {
                tweens.remove(at: i)
            }
        }
    }

    public class func tween(duration: Double) -> Tween {
        let tween = Tween(duration: duration)
        tweens.append(tween)
        return tween
    }

    public class func tweenValue(duration: Double, value: UnsafeMutablePointer<Float>, from: Float, to: Float) -> Tween {
        let tween = Tween(duration: duration)
        tweens.append(tween.onTween { [value] (progress: Double) in
            value.pointee = .lerp(from, to, Float(progress))
        })
        return tween
    }

    public class func tweenValue(duration: Double, value: UnsafeMutablePointer<CGFloat>, from: CGFloat, to: CGFloat) -> Tween {
        let tween = Tween(duration: duration)
        tweens.append(tween.onTween { [value] (progress: Double) in
            value.pointee = simd_mix(from, to, progress)
        })
        return tween
    }

    public class func tweenPosition(duration: Double, object: Object, from: simd_float3, to: simd_float3) -> Tween {
        let tween = Tween(duration: duration)
        tweens.append(tween.onTween { [weak object] (progress: Double) in
            object?.position = .lerp(from, to, Float(progress))
        })
        return tween
    }

    public class func tweenPosition(duration: Double, object: Object, to: simd_float3) -> Tween {
        var from: simd_float3 = object.position
        let tween = Tween(duration: duration)
            .onTweenStart { [weak object] in
                from = object?.position ?? from
            }
            .onTween { [weak object] (progress: Double) in
                object?.position = .lerp(from, to, Float(progress))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenScale(duration: Double, object: Object, from: simd_float3, to: simd_float3) -> Tween {
        let tween = Tween(duration: duration)
        tweens.append(
            tween.onTween { [weak object] (progress: Double) in
                object?.scale = .lerp(from, to, Float(progress))
            }
        )
        return tween
    }

    public class func tweenScale(duration: Double, object: Object, to: simd_float3) -> Tween {
        var from: simd_float3 = object.scale
        let tween = Tween(duration: duration)
            .onTweenStart { [weak object] in
                from = object?.scale ?? from
            }
            .onTween { [weak object] (progress: Double) in
                object?.scale = .lerp(from, to, Float(progress))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenOrientation(duration: Double, object: Object, from: simd_quatf, to: simd_quatf) -> Tween {
        let tween = Tween(duration: duration)
        tweens.append(tween.onTween { [weak object] (value: Double) in
            object?.orientation = .lerp(from, to, Float(value))
        })
        return tween
    }

    public class func tweenOrientation(duration: Double, object: Object, to: simd_quatf) -> Tween {
        var from: simd_quatf = object.orientation
        let tween = Tween(duration: duration)
            .onTweenStart { [weak object] in
                from = object?.orientation ?? from
            }
            .onTween { [weak object] (value: Double) in
                object?.orientation = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: FloatParameter, from: Float, to: Float) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: FloatParameter, to: Float) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: DoubleParameter, from: Double, to: Double) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_mix(from, to, value)
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: DoubleParameter, to: Double) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_mix(from, to, value)
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Float2Parameter, from: simd_float2, to: simd_float2) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Float2Parameter, to: simd_float2) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Float3Parameter, from: simd_float3, to: simd_float3) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Float3Parameter, to: simd_float3) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Float4Parameter, from: simd_float4, to: simd_float4) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Float4Parameter, to: simd_float4) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = .lerp(from, to, Float(value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: IntParameter, from: Int, to: Int) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = Int(simd_mix(Double(from), Double(to), value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: IntParameter, to: Int) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = Int(simd_mix(Double(from), Double(to), value))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Int2Parameter, from: simd_int2, to: simd_int2) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_int2(simd_mix(simd_double2(from), simd_double2(to), simd_double2(repeating: value)))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Int2Parameter, to: simd_int2) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_int2(simd_mix(simd_double2(from), simd_double2(to), simd_double2(repeating: value)))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Int3Parameter, from: simd_int3, to: simd_int3) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_int3(simd_mix(simd_double3(from), simd_double3(to), simd_double3(repeating: value)))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Int3Parameter, to: simd_int3) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_int3(simd_mix(simd_double3(from), simd_double3(to), simd_double3(repeating: value)))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Int4Parameter, from: simd_int4, to: simd_int4) -> Tween {
        let tween = Tween(duration: duration)
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_int4(simd_mix(simd_double4(from), simd_double4(to), simd_double4(repeating: value)))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenParameter(duration: Double, parameter: Int4Parameter, to: simd_int4) -> Tween {
        var from = parameter.value
        let tween = Tween(duration: duration)
            .onTweenStart { [weak parameter] in
                from = parameter?.value ?? from
            }
            .onTween { [weak parameter] (value: Double) in
                parameter?.value = simd_int4(simd_mix(simd_double4(from), simd_double4(to), simd_double4(repeating: value)))
            }
        tweens.append(tween)
        return tween
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: Float, to: Float) -> Tween? {
        guard let parameter = material.get(key) as? FloatParameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: Float) -> Tween? {
        guard let parameter = material.get(key) as? FloatParameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: simd_float2, to: simd_float2) -> Tween? {
        guard let parameter = material.get(key) as? Float2Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: simd_float2) -> Tween? {
        guard let parameter = material.get(key) as? Float2Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: simd_float3, to: simd_float3) -> Tween? {
        guard let parameter = material.get(key) as? Float3Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: simd_float3) -> Tween? {
        guard let parameter = material.get(key) as? Float3Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: simd_float4, to: simd_float4) -> Tween? {
        guard let parameter = material.get(key) as? Float4Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: simd_float4) -> Tween? {
        guard let parameter = material.get(key) as? Float4Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: Int, to: Int) -> Tween? {
        guard let parameter = material.get(key) as? IntParameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: Int) -> Tween? {
        guard let parameter = material.get(key) as? IntParameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: simd_int2, to: simd_int2) -> Tween? {
        guard let parameter = material.get(key) as? Int2Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: simd_int2) -> Tween? {
        guard let parameter = material.get(key) as? Int2Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: simd_int3, to: simd_int3) -> Tween? {
        guard let parameter = material.get(key) as? Int3Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: simd_int3) -> Tween? {
        guard let parameter = material.get(key) as? Int3Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, from: simd_int4, to: simd_int4) -> Tween? {
        guard let parameter = material.get(key) as? Int4Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, from: from, to: to)
    }

    public class func tweenMaterial(duration: Double, material: Material, key: String, to: simd_int4) -> Tween? {
        guard let parameter = material.get(key) as? Int4Parameter else { return nil }
        return tweenParameter(duration: duration, parameter: parameter, to: to)
    }

    public class func append(_ tween: Tween) {
        if !tweens.contains(tween) {
            tweens.append(tween)
        }
    }
}
