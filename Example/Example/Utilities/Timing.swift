//
//  Timing.swift
//  Example
//
//  Created by Reza Ali on 3/11/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Foundation

var messages: [String] = []
var startTimes: [ContinuousClock.Instant] = []

func start(_ message: String) {
    let count = messages.count
    messages.append(message)
    startTimes.append(.now)
    let spacing = Array(repeating: "\t", count: count).reduce("") { $0 + $1 }
    print("\(spacing)Starting: \(message)")
}

func end() {
    if let message = messages.popLast(), let startTime = startTimes.popLast() {
        let spacing = Array(repeating: "\t", count: messages.count).reduce("") { $0 + $1 }
        print("\(spacing)Finished: \(message): \(ContinuousClock.now - startTime)")
    }
}
