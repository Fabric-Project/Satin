//
//  Injections.swift
//  Satin
//
//  Created by Reza Ali on 3/3/23.
//

import Foundation
import Metal

public func injectComputeConstants(source: inout String) {
    source = source.replacingOccurrences(of: "// inject compute constants\n", with: (ComputeConstantsSource.get() ?? "\n") + "\n")
}

public func injectMeshConstants(source: inout String) {
    source = source.replacingOccurrences(of: "// inject mesh constants\n", with: (MeshConstantsSource.get() ?? "\n") + "\n")
}

public func injectVertexConstants(source: inout String) {
    source = source.replacingOccurrences(of: "// inject vertex constants\n", with: (VertexConstantsSource.get() ?? "\n") + "\n")
}

public func injectFragmentConstants(source: inout String) {
    source = source.replacingOccurrences(of: "// inject fragment constants\n", with: (FragmentConstantsSource.get() ?? "\n") + "\n")
}

public func injectPBRConstants(source: inout String) {
    source = source.replacingOccurrences(of: "// inject pbr constants\n", with: (PBRConstantsSource.get() ?? "\n") + "\n")
}

// MARK: - Constants

public func injectConstants(source: inout String, constants: [String]) {
    var injection = ""
    for constant in constants {
        injection += constant + "\n"
    }
    source = source.replacingOccurrences(of: "// inject constants\n", with: injection.isEmpty ? "\n" : injection + "\n")
}

// MARK: - Defines

public func injectDefines(source: inout String, defines: [ShaderDefine]) {
    var injection = ""
    for define in defines {
        injection += define.description
    }
    for define in ShaderDefine.defaultDefines {
        injection += define.description
    }
    source = source.replacingOccurrences(of: "// inject defines\n", with: injection.isEmpty ? "\n" : injection + "\n")
}

// MARK: - Vertex, VertexData, VertexUniforms, Vertex Shader

public func injectVertex(source: inout String, vertexDescriptor: MTLVertexDescriptor) {
    var vertexSource: String?
    if vertexDescriptor == SatinVertexDescriptor() {
        vertexSource = VertexSource.get()
    } else {
        var attributeDataType: [String] = []
        var attributeName: [String] = []
        var attributeAttribute: [String] = []

        for index in VertexAttributeIndex.allCases {
            let format = vertexDescriptor.attributes[index.rawValue].format
            if let dataType = format.dataType {
                attributeDataType.append(dataType)
                attributeName.append(index.name)
                attributeAttribute.append(index.description)
            }
        }

        var structMembers: [String] = []
        for i in 0 ..< attributeDataType.count {
            structMembers.append("\t\(attributeDataType[i]) \(attributeName[i]) [[attribute(VertexAttribute\(attributeAttribute[i]))]];")
        }

        if !structMembers.isEmpty {
            var generatedVertexSource = "typedef struct {\n"
            generatedVertexSource += structMembers.joined(separator: "\n")
            generatedVertexSource += "\n} Vertex;\n"
            vertexSource = generatedVertexSource
        }
    }

    source = source.replacingOccurrences(of: "// inject vertex\n", with: (vertexSource ?? "\n") + "\n")
}

public func injectVertexData(source: inout String) {
    source = source.replacingOccurrences(of: "// inject vertex data\n", with: (VertexDataSource.get() ?? "\n") + "\n")
}

public func injectVertexUniforms(source: inout String) {
    source = source.replacingOccurrences(of: "// inject vertex uniforms\n", with: (VertexUniformsSource.get() ?? "\n") + "\n")
}

public func injectPassThroughVertex(label: String, source: inout String) {
    let vertexFunctionName = label.camelCase + "Vertex"
    if !source.contains(vertexFunctionName),
       let passThroughVertexSource = PassThroughVertexPipelineSource.get()
    {
        let vertexSource = passThroughVertexSource.replacingOccurrences(of: "satinVertex", with: vertexFunctionName)
        source = source.replacingOccurrences(of: "// inject vertex shader\n", with: vertexSource + "\n")
    } else {
        source = source.replacingOccurrences(of: "// inject vertex shader\n", with: "\n")
    }
}

// MARK: - Instancing

public func injectInstanceMatrixUniforms(source: inout String) {
    source = source.replacingOccurrences(of: "// inject instance matrix uniforms\n", with: InstanceMatrixUniformsSource.get() ?? "\n")
}

public func injectInstancingArgs(source: inout String, instancing: Bool) {
    let injection =
        """
        \tuint instanceID [[instance_id]],
        \tconst device InstanceMatrixUniforms *instanceUniforms [[buffer(VertexBufferInstanceMatrixUniforms)]],\n
        """
    source = source.replacingOccurrences(of: "// inject instancing args\n", with: instancing ? injection : "")
}

// MARK: - Lights

public func injectLighting(source: inout String, lighting: Bool) {
    source = source.replacingOccurrences(of: "// inject lighting\n", with: lighting ? (LightingSource.get() ?? "\n") : "\n")
}

public func injectLightingArgs(source: inout String, lighting: Bool) {
    let injection = "\tconstant LightData *lights [[buffer(FragmentBufferLighting)]],\n"
    source = source.replacingOccurrences(of: "// inject lighting args\n", with: lighting ? injection : "")
}

// MARK: - Shadows

public func injectShadowData(source: inout String, receiveShadow: Bool, shadowCount: Int) {
    var injection = ""
    if receiveShadow, shadowCount > 0, let shadowDataSource = ShadowDataSource.get() {
        injection = shadowDataSource
    }
    source = source.replacingOccurrences(of: "// inject shadow data\n", with: injection)
}

public func injectShadowBuffer(source: inout String, receiveShadow: Bool, shadowCount: Int) {
    var injection = ""
    if receiveShadow, shadowCount > 0 {
        injection += "struct Shadows {\n"
        injection += "\tconstant ShadowData *data [[buffer(FragmentBufferShadowData)]];\n"
        injection += "\tarray<depth2d<float>, \(shadowCount)> textures [[texture(FragmentTextureShadow0)]];\n"
        injection += "};\n\n"
    }
    source = source.replacingOccurrences(of: "// inject shadow buffer\n", with: injection)
}

public func injectShadowFunction(source: inout String, receiveShadow: Bool, shadowCount: Int) {
    var injection = ""
    if receiveShadow, shadowCount > 0, let shadowFunctionSource = ShadowFunctionSource.get() {
        injection = shadowFunctionSource
    }
    source = source.replacingOccurrences(of: "// inject shadow function\n", with: injection)
}

public func injectPassThroughShadowVertex(label: String, source: inout String) {
    let shadowFunctionName = label.camelCase + "ShadowVertex"
    if !source.contains(shadowFunctionName),
       let passThroughShadowSource = PassThroughShadowPipelineSource.get()
    {
        let shadowSource = passThroughShadowSource.replacingOccurrences(of: "satinShadowVertex", with: shadowFunctionName)
        source = source.replacingOccurrences(of: "// inject shadow shader\n", with: shadowSource + "\n")
    } else {
        source = source.replacingOccurrences(of: "// inject shadow shader\n", with: "\n")
    }
}

public func injectShadowCoords(source: inout String, receiveShadow: Bool, shadowCount: Int) {
    var injection = ""
    if receiveShadow {
        for i in 0 ..< shadowCount {
            injection += "\tfloat4 shadowCoord\(i);\n"
        }
    }
    source = source.replacingOccurrences(of: "// inject shadow coords\n", with: injection)
}

public func injectShadowVertexArgs(source: inout String, receiveShadow: Bool) {
    let injection = "constant float4x4 *shadowMatrices [[buffer(VertexBufferShadowMatrices)]],\n"
    source = source.replacingOccurrences(of: "// inject shadow vertex args\n", with: receiveShadow ? injection : "")
}

public func injectShadowFragmentArgs(source: inout String, receiveShadow: Bool, shadowCount: Int) {
    var injection = ""
    if receiveShadow, shadowCount > 0 {
        injection += "constant Shadows &shadows [[buffer(FragmentBufferShadows)]],\n"
    }

    source = source.replacingOccurrences(of: "// inject shadow fragment args\n", with: injection)
}

public func injectShadowVertexCalc(source: inout String, receiveShadow: Bool, shadowCount: Int) {
    var injection = ""
    if receiveShadow {
        for i in 0 ..< shadowCount {
            if i > 0 {
                injection += "\t"
            }
            injection +=
                """
                #if defined(INSTANCING)
                out.shadowCoord\(i) = shadowMatrices[\(i)] * instanceUniforms[instanceID].modelMatrix * float4(in.position.xyz, 1.0);\n
                #else
                out.shadowCoord\(i) = shadowMatrices[\(i)] * vertexUniforms[amp_id].modelMatrix * float4(in.position.xyz, 1.0);\n
                #endif\n\n
                """
        }
    }
    source = source.replacingOccurrences(of: "// inject shadow vertex calc\n", with: injection)
}

public func injectShadowFragmentCalc(source: inout String, receiveShadow: Bool, shadowCount: Int) {
    var injection = ""

    if receiveShadow, shadowCount > 0 {
        injection += "float shadow = 1.0;\n"
        injection += "\tconstexpr sampler ss(coord::normalized, address::clamp_to_edge, filter::linear, compare_func::greater_equal);\n"
        for i in 0 ..< shadowCount {
            injection += "\tshadow *= calculateShadow(in.shadowCoord\(i), shadows.textures[\(i)], shadows.data[\(i)], ss);\n"
        }
        injection += "\toutColor.rgb *= shadow;\n\n"
    }

    source = source.replacingOccurrences(of: "// inject shadow fragment calc\n", with: injection)
}
