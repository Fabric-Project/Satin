//
//  ParameterGroup.swift
//  Satin
//
//  Created by Reza Ali on 10/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Foundation
import Metal
import simd
import Observation

@Observable public final class ParameterGroup: Codable, CustomStringConvertible {
    public let id: String = UUID().uuidString

    public var description: String {
        var dsc = "\(type(of: self)): \(label)\n"
        for param in params {
            dsc += param.description + "\n"
        }
        return dsc
    }

    public var label = ""
    public private(set) var params: [any Parameter] = [] {
        didSet {
            _updateSize = true
            _updateStride = true
            _updateAlignment = true
            _reallocateData = true
            _updateData = true
        }
    }

    public var paramsMap: [String: any Parameter] = [:]

    private var paramSubscriptions: [String: AnyCancellable] = [:]

    public let parameterAddedPublisher = PassthroughSubject<any Parameter, Never>()
    public let parameterRemovedPublisher = PassthroughSubject<any Parameter, Never>()
    public let parameterUpdatedPublisher = PassthroughSubject<any Parameter, Never>()

    public let loadedPublisher = PassthroughSubject<ParameterGroup, Never>()
    public let savedPublisher = PassthroughSubject<ParameterGroup, Never>()
    public let clearedPublisher = PassthroughSubject<ParameterGroup, Never>()

    deinit {
        params = []
        paramsMap = [:]
        paramSubscriptions = [:]

        if _dataAllocated {
            _data.deallocate()
        }
    }

    public init(_ label: String = "", _ parameters: [any Parameter] = []) {
        self.label = label
        append(parameters)
    }

    public func append(_ parameters: [any Parameter]) {
        for p in parameters {
            append(p)
        }
    }

    public func append(_ param: some Parameter) {
        params.append(param)
        paramsMap[param.label] = param
        paramSubscriptions[param.label] = param.valuePublisher.sink { [weak self, weak param] _ in
            guard let self = self, let param else { return }
            self._updateData = true
//            self.objectWillChange.send()
            self.parameterUpdatedPublisher.send(param)
        }

        parameterAddedPublisher.send(param)
    }

    public func remove(_ param: any Parameter) {
        let key = param.label
        paramsMap.removeValue(forKey: key)
        paramSubscriptions.removeValue(forKey: key)

        for (i, p) in params.enumerated() {
            if p.label == key {
                params.remove(at: i)
                break
            }
        }

        parameterRemovedPublisher.send(param)
    }

    public func clear() {
        params = []
        paramsMap = [:]
        paramSubscriptions = [:]
        clearedPublisher.send(self)
    }

    public func copy(_ incomingParams: ParameterGroup) {
        clear()
        label = incomingParams.label
        for param in incomingParams.params {
            let label = param.label
            if let p = param as? FloatParameter {
                append(FloatParameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? Float2Parameter {
                append(Float2Parameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? Float3Parameter {
                append(Float3Parameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? PackedFloat3Parameter {
                append(PackedFloat3Parameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? Float4Parameter {
                append(Float4Parameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? IntParameter {
                append(IntParameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? Int2Parameter {
                append(Int2Parameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? Int3Parameter {
                append(Int3Parameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? Int4Parameter {
                append(Int4Parameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? DoubleParameter {
                append(DoubleParameter(label, p.value, p.min, p.max, p.controlType))
            } else if let p = param as? BoolParameter {
                append(BoolParameter(label, p.value, p.controlType))
            } else if let p = param as? Float2x2Parameter {
                append(Float2x2Parameter(label, p.value, p.controlType))
            } else if let p = param as? Float3x3Parameter {
                append(Float3x3Parameter(label, p.value, p.controlType))
            } else if let p = param as? Float4x4Parameter {
                append(Float4x4Parameter(label, p.value, p.controlType))
            } else if let p = param as? StringParameter {
                append(StringParameter(label, p.value, p.options, p.controlType))
            } else if let p = param as? UInt32Parameter {
                append(UInt32Parameter(label, p.value, p.min, p.max, p.controlType))
            }
        }
    }

    public func clone() -> ParameterGroup {
        let copy = ParameterGroup()
        copy.copy(self)
        return copy
    }

    public func setFrom(_ incomingParams: ParameterGroup, setValues: Bool = false, setOptions: Bool = true, setControls: Bool = true) {
        var incomingKeysOrdered: [String] = []
        for param in incomingParams.params {
            incomingKeysOrdered.append(param.label)
        }

        let incomingKeys = Set(incomingKeysOrdered)
        let exisitingKeys = Set(self.paramsMap.keys)

        let newKeys = incomingKeys.subtracting(exisitingKeys)
        let commonKeys = exisitingKeys.intersection(incomingKeys)
        let removedKeys = exisitingKeys.subtracting(incomingKeys)

        for key in removedKeys {
            if let param = self.paramsMap[key] {
                remove(param)
            }
        }

        for key in newKeys {
            if let param = incomingParams.paramsMap[key] {
                append(param.clone())
            }
        }

        for key in commonKeys {
            if let inParam = incomingParams.paramsMap[key] {
                setParameterFrom(
                    param: inParam,
                    setValue: setValues,
                    setOptions: setOptions,
                    setControl: setControls,
                    append: false
                )
            }
        }

        let paramsMap = self.paramsMap

        clear()

        for key in incomingKeysOrdered {
            if let param = paramsMap[key] {
                append(param)
            }
        }
    }

    public func setValuesFrom(_ incomingParams: ParameterGroup) {
        let incomingKeys = Set(incomingParams.paramsMap.keys)
        let exisitingKeys = Set(paramsMap.keys)
        let commonKeys = exisitingKeys.intersection(incomingKeys)
        for key in commonKeys {
            if let inParam = incomingParams.paramsMap[key] {
                setParameterFrom(
                    param: inParam,
                    setValue: true,
                    setOptions: false,
                    setControl: false,
                    append: false
                )
            }
        }
    }

    private enum CodingKeys: CodingKey {
        case label
        case params
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            label = try container.decode(String.self, forKey: .label)
        } catch {
            print(error.localizedDescription)
        }
        let baseParams = try container.decode([AnyParameter].self, forKey: .params)
        for baseParam in baseParams {
            let param = baseParam.base
            params.append(param)
            paramsMap[param.label] = param
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(params.map(AnyParameter.init), forKey: .params)
    }

    public func save(_ url: URL, ignoreControlTypeNone: Bool = false) {
        do {
            let jsonEncoder = JSONEncoder()
            jsonEncoder.userInfo[.ignoreControlTypeNone] = ignoreControlTypeNone
            jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload: Data = try jsonEncoder.encode(self)
            try payload.write(to: url)
            savedPublisher.send(self)
        } catch {
            print(error.localizedDescription)
        }
    }

    public func load(_ url: URL, ignoreControlTypeNone: Bool = false, values: Bool = true, options: Bool = true, controls: Bool = true, append: Bool = true) {
        do {
            let jsonDecoder = JSONDecoder()
            let data = try Data(contentsOf: url)
            let loaded = try jsonDecoder.decode(ParameterGroup.self, from: data)
            for param in loaded.params {
                setParameterFrom(
                    param: param,
                    setValue: values,
                    setOptions: options,
                    setControl: controls,
                    append: append,
                    ignoreControlTypeNone: ignoreControlTypeNone
                )
            }

            loadedPublisher.send(self)
        } catch {
            print(error.localizedDescription)
        }
    }

    func setParameterFrom(param: any Parameter, setValue: Bool, setOptions: Bool, setControl: Bool, append: Bool, ignoreControlTypeNone: Bool = false) {
        let label = param.label
        let canSetValue = !(param.controlType == .none && ignoreControlTypeNone) && setValue
        if ignoreControlTypeNone {
            print(" \(param.label) - canSetValue: \(canSetValue)")
        }
        if append, paramsMap[label] == nil {
            self.append(param.clone())
        } else if let mp = paramsMap[label] {
            if setControl {
                mp.controlType = param.controlType
            }
            if let p = param as? FloatParameter, let mfp = mp as? FloatParameter {
                if canSetValue {
                    mfp.value = p.value
                }
                if setOptions {
                    mfp.min = p.min
                    mfp.max = p.max
                }
            } else if let p = param as? Float2Parameter, let mfp = mp as? Float2Parameter {
                if canSetValue {
                    mfp.value = p.value
                }
                if setOptions {
                    mfp.min = p.min
                    mfp.max = p.max
                }
            } else if let p = param as? Float3Parameter, let mfp = mp as? Float3Parameter {
                if canSetValue {
                    mfp.value = p.value
                }
                if setOptions {
                    mfp.min = p.min
                    mfp.max = p.max
                }
            } else if let p = param as? PackedFloat3Parameter, let mfp = mp as? PackedFloat3Parameter {
                if canSetValue {
                    mfp.value = p.value
                }
                if setOptions {
                    mfp.min = p.min
                    mfp.max = p.max
                }
            } else if let p = param as? Float4Parameter, let mfp = mp as? Float4Parameter {
                if canSetValue {
                    mfp.value = p.value
                }
                if setOptions {
                    mfp.min = p.min
                    mfp.max = p.max
                }
            } else if let p = param as? IntParameter, let mip = mp as? IntParameter {
                if canSetValue {
                    mip.value = p.value
                }
                if setOptions {
                    mip.min = p.min
                    mip.max = p.max
                }

            } else if let p = param as? Int2Parameter, let mip = mp as? Int2Parameter {
                if canSetValue {
                    mip.value = p.value
                }
                if setOptions {
                    mip.min = p.min
                    mip.max = p.max
                }

            } else if let p = param as? Int3Parameter, let mip = mp as? Int3Parameter {
                if canSetValue {
                    mip.value = p.value
                }
                if setOptions {
                    mip.min = p.min
                    mip.max = p.max
                }

            } else if let p = param as? DoubleParameter, let mdp = mp as? DoubleParameter {
                if canSetValue {
                    mdp.value = p.value
                }
                if canSetValue {
                    mdp.min = p.min
                    mdp.max = p.max
                }
            } else if let p = param as? BoolParameter, let mbp = mp as? BoolParameter {
                if canSetValue {
                    mbp.value = p.value
                }
            } else if let p = param as? StringParameter, let mbp = mp as? StringParameter {
                if canSetValue {
                    mbp.value = p.value
                }
                if setOptions {
                    mbp.options = p.options
                }
            } else if let p = param as? UInt32Parameter, let mbp = mp as? UInt32Parameter {
                if canSetValue {
                    mbp.value = p.value
                }
                if setOptions {
                    mbp.min = p.min
                    mbp.max = p.max
                }
            } else if let p = param as? Float3x3Parameter, let mbp = mp as? Float3x3Parameter {
                if canSetValue {
                    mbp.value = p.value
                }

            } else if let p = param as? Float4x4Parameter, let mbp = mp as? Float4x4Parameter {
                if canSetValue {
                    mbp.value = p.value
                }
            }
        }
    }

    @ObservationIgnored private var _size = 0
    @ObservationIgnored private var _stride = 0
    @ObservationIgnored private var _alignment = 0
    @ObservationIgnored private var _dataAllocated = false
    @ObservationIgnored private var _reallocateData = false
    @ObservationIgnored private var _updateSize = true
    @ObservationIgnored private var _updateStride = true
    @ObservationIgnored private var _updateAlignment = true
    @ObservationIgnored private var _updateData = true

    private func updateSize() {
        var result = 0
        for param in params {
            let size = param.size
            let alignment = param.alignment
            let rem = result % alignment
            if rem > 0 {
                let offset = alignment - rem
                result += offset
            }
            result += size
        }
        _size = result
    }

    @ObservationIgnored public var size: Int {
        if _updateSize {
            updateSize()
            _updateSize = false
        }
        return _size
    }

    private func updateStride() {
        var result = size
        let alignment = self.alignment
        let rem = result % alignment
        if rem > 0 {
            let offset = alignment - rem
            result += offset
        }
        _stride = result
    }

    public var stride: Int {
        if _updateStride {
            updateStride()
            _updateStride = false
        }
        return _stride
    }

    private func updateAlignment() {
        var result = 0
        for param in params {
            result = max(result, param.alignment)
        }
        _alignment = result
    }

    public var alignment: Int {
        if _updateAlignment {
            updateAlignment()
            _updateAlignment = false
        }
        return _alignment
    }

    public var structString: String {
        var structName = label.replacingOccurrences(of: " ", with: "")
        structName = structName.camelCase
        structName = structName.prefix(1).capitalized + structName.dropFirst()
        var source = "typedef struct {\n"
        for param in params {
            source += "\t \(param.string) \(param.label.camelCase);\n"
        }
        source += "} \(structName);\n\n"
        return source
    }

    @ObservationIgnored private lazy var _data: UnsafeMutableRawPointer = {
        _dataAllocated = true
        return UnsafeMutableRawPointer.allocate(byteCount: size, alignment: alignment)
    }()

    private func allocateData() -> UnsafeMutableRawPointer {
        if _dataAllocated {
            _data.deallocate()
        }
        _dataAllocated = true
        return UnsafeMutableRawPointer.allocate(byteCount: size, alignment: alignment)
    }

    @ObservationIgnored public var data: UnsafeRawPointer {
        if _reallocateData {
            _data = allocateData()
            _reallocateData = false
        }
        if _updateData {
            updateData()
            _updateData = false
        }
        return UnsafeRawPointer(_data)
    }

    private func updateData() {
        var pointer = _data
        var offset = 0
        for param in params {
            pointer = param.writeData(pointer: pointer, offset: &offset)
        }
    }

    public func set(_ name: String, _ value: [Float]) {
        let count = value.count
        if count == 1 {
            set(name, value[0])
        } else if count == 2 {
            set(name, simd_make_float2(value[0], value[1]))
        } else if count == 3 {
            set(name, simd_make_float3(value[0], value[1], value[2]))
        } else if count == 4 {
            set(name, simd_make_float4(value[0], value[1], value[2], value[3]))
        }
    }

    public func set(_ name: String, _ value: [Int]) {
        let count = value.count
        if count == 1 {
            set(name, value[0])
        } else if count == 2 {
            set(name, simd_make_int2(Int32(value[0]), Int32(value[1])))
        } else if count == 3 {
            set(name, simd_make_int3(Int32(value[0]), Int32(value[1]), Int32(value[2])))
        } else if count == 4 {
            set(name, simd_make_int4(Int32(value[0]), Int32(value[1]), Int32(value[2]), Int32(value[3])))
        }
    }

    public func set(_ name: String, _ value: Float) {
        if let param = get(name), let p = param as? FloatParameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_float2) {
        if let param = get(name), let p = param as? Float2Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_float3) {
        if let param = get(name), let p = param as? Float3Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: MTLPackedFloat3) {
        if let param = get(name), let p = param as? PackedFloat3Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_float4) {
        if let param = get(name), let p = param as? Float4Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_float2x2) {
        if let param = get(name), let p = param as? Float2x2Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_float3x3) {
        if let param = get(name), let p = param as? Float3x3Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_float4x4) {
        if let param = get(name), let p = param as? Float4x4Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: Int) {
        if let param = get(name), let p = param as? IntParameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_int2) {
        if let param = get(name), let p = param as? Int2Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_int3) {
        if let param = get(name), let p = param as? Int3Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: simd_int4) {
        if let param = get(name), let p = param as? Int4Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: UInt32) {
        if let param = get(name), let p = param as? UInt32Parameter {
            p.value = value
        }
    }

    public func set(_ name: String, _ value: Bool) {
        if let param = get(name), let p = param as? BoolParameter {
            p.value = value
        }
    }

    public func get(_ name: String) -> (any Parameter)? {
        return paramsMap[name] ?? paramsMap[name.titleCase]
    }

    public func get<T>(_ name: String, as: T.Type) -> T? {
        return get(name) as? T
    }
}

extension ParameterGroup: Equatable {
    public static func == (lhs: ParameterGroup, rhs: ParameterGroup) -> Bool {
        return lhs.id == rhs.id
    }
}
