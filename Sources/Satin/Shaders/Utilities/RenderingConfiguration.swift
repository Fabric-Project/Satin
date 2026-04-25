//
//  RenderingConfiguration.swift
//
//
//  Created by Reza Ali on 6/15/23.
//

import Foundation
import Metal

public struct TessellationDescriptor: Equatable, CustomStringConvertible {
    public let partitionMode: MTLTessellationPartitionMode
    public let factorStepFunction: MTLTessellationFactorStepFunction
    public let outputWindingOrder: MTLWinding
    public let controlPointIndexType: MTLTessellationControlPointIndexType

    public var description: String {
        var output = "TessellationDescriptor: \n"
        output += "\tpartitionMode: \(partitionMode)\n"
        output += "\tfactorStepFunction: \(factorStepFunction)\n"
        output += "\toutputWindingOrder: \(outputWindingOrder)\n"
        output += "\tcontrolPointIndexType: \(controlPointIndexType)\n"
        return output
    }
}

public struct RenderingConfiguration: Hashable {
    // Blending
    var blending = ShaderBlending()

    // Vertex Descriptor
    var vertexDescriptor = SatinVertexDescriptor()
    var tessellationDescriptor: TessellationDescriptor?

    // Instancing
    var instancing: Bool = false

    // Lighting
    var lighting: Bool = false
    var lightCount: Int = 0

    // Shadows
    var castShadow: Bool = false
    var receiveShadow: Bool = false
    var shadowCount: Int = 0

    var defines: [ShaderDefine] = []
    var constants: [String] = []

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blending)
        hasher.combine(vertexDescriptor)

        hasher.combine(instancing)
        hasher.combine(lighting)
        hasher.combine(lightCount)

        hasher.combine(castShadow)
        hasher.combine(receiveShadow)
        hasher.combine(shadowCount)

        if !defines.isEmpty { hasher.combine(defines) }
        if !constants.isEmpty { hasher.combine(constants) }
    }

    func getDefines() -> [ShaderDefine] {
        var results = defines

        for attribute in VertexAttributeIndex.allCases {
            switch vertexDescriptor.attributes[attribute.rawValue].format {
                case .invalid:
                    continue
                default:
                    results.append(ShaderDefine(key: attribute.shaderDefine, value: NSString(string: "true")))
            }
        }

        if instancing { results.append(ShaderDefine(key: "INSTANCING", value: NSString(string: "true"))) }
        if lighting { results.append(ShaderDefine(key: "LIGHTING", value: NSString(string: "true"))) }
        if lightCount > 0 { results.append(ShaderDefine(key: "MAX_LIGHTS", value: NSNumber(value: lightCount))) }
        if receiveShadow { results.append(ShaderDefine(key: "HAS_SHADOWS", value: NSString(string: "true"))) }
        if shadowCount > 0 { results.append(ShaderDefine(key: "SHADOW_COUNT", value: NSNumber(value: shadowCount))) }

        return results
    }

    func getConstants() -> [String] {
        return constants
    }
}

extension RenderingConfiguration: Equatable {
    public static func == (lhs: RenderingConfiguration, rhs: RenderingConfiguration) -> Bool {
        lhs.blending == rhs.blending &&
            lhs.vertexDescriptor == rhs.vertexDescriptor &&
            lhs.instancing == rhs.instancing &&
            lhs.lighting == rhs.lighting &&
            lhs.lightCount == rhs.lightCount &&
            lhs.castShadow == rhs.castShadow &&
            lhs.receiveShadow == rhs.receiveShadow &&
            lhs.shadowCount == rhs.shadowCount &&
            lhs.defines == rhs.defines &&
            lhs.constants == rhs.constants &&
            lhs.tessellationDescriptor == rhs.tessellationDescriptor
    }
}

extension RenderingConfiguration: CustomStringConvertible {
    public var description: String {
        var output = "RenderingConfiguration: \n"

        output += "\t\t \(blending.description)"

        output += "\t\t instancing: \(instancing)\n"
        output += "\t\t lighting: \(lighting)\n"
        output += "\t\t lightCount: \(lightCount)\n"
        output += "\t\t castShadow: \(castShadow)\n"
        output += "\t\t receiveShadow: \(receiveShadow)\n"
        output += "\t\t shadowCount: \(shadowCount)\n"

        output += "\t\t vertexDecriptor: \(vertexDescriptor)\n"
        if let tessellationDescriptor {
            output += "\t\t tessellationDescriptor: \(tessellationDescriptor)\n"
        }

        if !defines.isEmpty {
            output += "\t\t defines:\n"
            for (index, define) in defines.enumerated() {
                output += "\t\t\t \(index): \(define.description)"
            }
        }

        if !constants.isEmpty {
            output += "\t\t constants:\n"
            for (index, constant) in constants.enumerated() {
                output += "\t\t\t \(index): \(constant)\n"
            }
        }

        return output
    }
}
