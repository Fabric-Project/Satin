//
//  Metal+Extensions.swift
//  Satin
//
//  Created by Reza Ali on 11/17/22.
//

import Foundation
import Metal

//extension MTLTriangleFillMode: @retroactive Decodable {}
//extension MTLTriangleFillMode: @retroactive Encodable {}
extension MTLTriangleFillMode: @retroactive Codable {}
extension MTLCullMode: @retroactive Codable {}
extension MTLPrimitiveType: @retroactive Codable {}
extension MTLWinding: @retroactive Codable {}
extension MTLIndexType: @retroactive Codable {}

extension MTLCompareFunction: @retroactive Codable {}
extension MTLBlendOperation: @retroactive Codable {}
extension MTLBlendFactor: @retroactive Codable {}
