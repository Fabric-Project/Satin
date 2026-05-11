//
//  VertexAttribute.swift
//
//
//  Created by Reza Ali on 8/2/23.
//

import Foundation
import Metal

open class VertexAttribute: Equatable {
    public let id: String = UUID().uuidString

    open var type: AttributeType { .generic }
    open var format: MTLVertexFormat { type.format }
    open var count: Int { 0 } // this represents how many elements we have in a BufferAttribute (5 positions) or how many vertices we have in an InterleavedBufferAttribute

    open var size: Int { 0 }
    open var stride: Int { 0 }
    open var alignment: Int { 0 }
    open var components: Int { 0 }

    open var stepRate: Int { 1 }
    open var stepFunction: MTLVertexStepFunction { .perVertex }

    public static func == (lhs: VertexAttribute, rhs: VertexAttribute) -> Bool {
        lhs === rhs
    }
}
