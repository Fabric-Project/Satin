//
//  GenericParameter.swift
//
//
//  Created by Reza Ali on 4/7/22.
//

import Combine
import Foundation

public class GenericParameter<T: Codable & Equatable>: Parameter, ParameterChannelMember {
    public var id: UUID

    public typealias ValueType = T

    // Delegate
    public let valuePublisher = PassthroughSubject<ValueType, Never>()

    // Getable Properties
    public var type: ParameterType { .generic }
    public var string: String { type.string }

    // Computed Properties
    public var size: Int { return MemoryLayout<ValueType>.size }
    public var stride: Int { return MemoryLayout<ValueType>.stride }
    public var alignment: Int { return MemoryLayout<ValueType>.alignment }

    // Setable Properties
    public var controlType = ControlType.none
    public var label: String

    public var description: String = ""
    
    public var debugDescription: String {
        "Label: \(label) type: \(string) value: \(value) controlType: \(controlType)"
    }

    // Maybe a bit too verbose?
    public var valueDidChange:Bool = true
        
    public var value: ValueType
    {
        didSet
        {
            if oldValue != self.value
            {
                self.valueDidChange = true
                valuePublisher.send(self.value)
                valueDidChangeForMain()
            }
        }
    }

    // MARK: - Main-thread mirror and UI writes

    public let mainValuePublisher = PassthroughSubject<ValueType, Never>()

    public var mainValue: ValueType { channel == nil ? value : _mainValue }

    /// Set while the parameter's group has a `renderQueue`; assigned before frames run.
    private(set) var channel: ParameterChannel?

    var isQueuedForApply = false
    var isQueuedForPublish = false

    /// Main thread only.
    private var _mainValue: ValueType
    private var submitSequence: UInt64 = 0

    /// Under the channel's lock.
    private var submittedValues = ContiguousArray<ValueType>()
    private var submittedSequence: UInt64 = 0
    private var publishedValue: ValueType?
    private var publishedSequence: UInt64 = 0

    /// Owner only.
    private var applyingValues = ContiguousArray<ValueType>()
    private var appliedSequence: UInt64 = 0

    public func submit(_ newValue: ValueType) {
        guard let channel else {
            value = newValue
            return
        }
        submitSequence &+= 1
        let sequence = submitSequence
        let keepsEveryValue = controlType == .button
        channel.lock.sync {
            if !keepsEveryValue { submittedValues.removeAll(keepingCapacity: true) }
            submittedValues.append(newValue)
            submittedSequence = sequence
        }
        if _mainValue != newValue {
            _mainValue = newValue
            mainValuePublisher.send(newValue)
        }
        channel.scheduleApply(self)
    }

    func applySubmittedValues(from drainingChannel: ParameterChannel) {
        guard let channel, channel === drainingChannel else { return }
        channel.lock.sync {
            swap(&submittedValues, &applyingValues)
            appliedSequence = submittedSequence
        }
        for submitted in applyingValues { value = submitted }
        applyingValues.removeAll(keepingCapacity: true)
    }

    private func valueDidChangeForMain() {
        guard let channel else {
            mainValuePublisher.send(value)
            return
        }
        let value = value
        let sequence = appliedSequence
        channel.lock.sync {
            publishedValue = value
            publishedSequence = sequence
        }
        channel.schedulePublish(self)
    }

    func publishToMain(from drainingChannel: ParameterChannel) {
        guard let channel, channel === drainingChannel else { return }
        let (published, sequence) = channel.lock.sync { (publishedValue, publishedSequence) }
        // A newer submit is still on its way to the owner: keep showing it.
        guard let published, sequence >= submitSequence, _mainValue != published else { return }
        _mainValue = published
        mainValuePublisher.send(published)
    }

    /// Binds the parameter to its owner's channel, once: ownership is for the parameter's life.
    /// A second group on the same queue keeps the first channel, so one lock guards its values.
    func attach(to newChannel: ParameterChannel?) {
        guard let newChannel else { return }
        if let channel {
            precondition(channel.renderQueue === newChannel.renderQueue,
                         "Parameter \(label) is owned by one render queue and can't move to another")
            return
        }
        channel = newChannel
        _mainValue = value
    }

    public var defaultValue: ValueType

    private enum CodingKeys: String, CodingKey {
        case id
        case controlType
        case label
        case value
        case defaultValue
        case description
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decode(UUID.self, forKey: .id)
        self.id = id
        
        self.controlType = try container.decode(ControlType.self, forKey: .controlType)

        self.label = try container.decode(String.self, forKey: .label)

        let value = try container.decode(ValueType.self, forKey: .value)

        self.value = value
        self._mainValue = value

        if let defaultValue = try container.decodeIfPresent(ValueType.self, forKey: .defaultValue) {
            self.defaultValue = defaultValue
        }
        else {
            defaultValue = value
        }
        
        if let description = try container.decodeIfPresent(String.self, forKey: .description)
        {
            self.description = description
        }
        else
        {
            self.description = ""
        }
        
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(controlType, forKey: .controlType)
        try container.encode(label, forKey: .label)
        try container.encode(description, forKey: .description)

        var saveDefaultValueInPlaceOfValue = false
        if controlType == .none, let ignoreControlTypeNone = encoder.userInfo[.ignoreControlTypeNone] as? Bool {
            saveDefaultValueInPlaceOfValue = ignoreControlTypeNone
        }

        try container.encode(saveDefaultValueInPlaceOfValue ? defaultValue : value, forKey: .value)
        try container.encode(defaultValue, forKey: .defaultValue)
    }

    public init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description:String = "") {
        self.id = UUID()
        self.label = label
        self.value = value
        self._mainValue = value
        self.defaultValue = value
        self.controlType = controlType
        self.description = description
    }

    public func alignData(pointer: UnsafeMutableRawPointer, offset: inout Int) -> UnsafeMutableRawPointer {
        var data = pointer
        let rem = offset % alignment
        if rem > 0 {
            let remOffset = alignment - rem
            data += remOffset
            offset += remOffset
        }
        return data
    }

    public func writeData(pointer: UnsafeMutableRawPointer, offset: inout Int) -> UnsafeMutableRawPointer {
        var data = alignData(pointer: pointer, offset: &offset)
        data.storeBytes(of: value, as: ValueType.self)
        data += size
        offset += size
        return data
    }

    public func clone() -> any Parameter {
        GenericParameter<ValueType>(label, value, controlType, description)
    }
}

public class GenericParameterWithMinMax<T: Codable & Equatable>: GenericParameter<T> {
    public typealias ValueType = T

    public let minValuePublisher = PassthroughSubject<ValueType, Never>()

    public var min: ValueType {
        didSet {
            minValuePublisher.send(min)
            valuePublisher.send(value)
            rangeDidChangeForMain()
        }
    }

    public let maxValuePublisher = PassthroughSubject<ValueType, Never>()

    public var max: ValueType {
        didSet {
            maxValuePublisher.send(max)
            valuePublisher.send(value)
            rangeDidChangeForMain()
        }
    }

    public let mainMinValuePublisher = PassthroughSubject<ValueType, Never>()
    public let mainMaxValuePublisher = PassthroughSubject<ValueType, Never>()

    /// `min` and `max` as the main thread sees them; see `mainValue`.
    public var mainMin: ValueType { channel == nil ? min : _mainMin }
    public var mainMax: ValueType { channel == nil ? max : _mainMax }

    /// Main thread only.
    private var _mainMin: ValueType
    private var _mainMax: ValueType
    /// Under the channel's lock.
    private var publishedRange: (min: ValueType, max: ValueType)?

    private func rangeDidChangeForMain() {
        guard let channel else {
            mainMinValuePublisher.send(min)
            mainMaxValuePublisher.send(max)
            return
        }
        let range = (min, max)
        channel.lock.sync { publishedRange = range }
        channel.schedulePublish(self)
    }

    override func publishToMain(from drainingChannel: ParameterChannel) {
        super.publishToMain(from: drainingChannel)
        guard let channel, channel === drainingChannel, let range = channel.lock.sync(execute: { publishedRange }) else { return }
        if _mainMin != range.min {
            _mainMin = range.min
            mainMinValuePublisher.send(range.min)
        }
        if _mainMax != range.max {
            _mainMax = range.max
            mainMaxValuePublisher.send(range.max)
        }
    }

    override func attach(to newChannel: ParameterChannel?) {
        let wasAttached = channel != nil
        super.attach(to: newChannel)
        guard !wasAttached, channel != nil else { return }
        _mainMin = min
        _mainMax = max
    }

    private enum CodingKeys: String, CodingKey {
        case min
        case max
    }

    public init(_ label: String, _ value: ValueType, _ min: ValueType, _ max: ValueType, _ controlType: ControlType = .none,  _ description:String = "") {
        self.min = min
        self.max = max
        self._mainMin = min
        self._mainMax = max
        super.init(label, value, controlType, description)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.min = try container.decode(ValueType.self, forKey: .min)
        self.max = try container.decode(ValueType.self, forKey: .max)
        self._mainMin = min
        self._mainMax = max
        try super.init(from: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(min, forKey: .min)
        try container.encode(max, forKey: .max)
    }

    override public func clone() -> any Parameter {
        GenericParameterWithMinMax<ValueType>(label, value, min, max, controlType, description)
    }
}
