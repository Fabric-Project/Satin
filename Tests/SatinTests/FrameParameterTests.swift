@testable import Satin
import Metal
import simd
import XCTest

/// The parameters the renderer writes into every lit material each frame are found by name once,
/// then written directly, until the material's parameters change structure.
final class FrameParameterTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    func testAStructureChangeAdvancesTheRevisionAndAValueChangeDoesNot() {
        let group = ParameterGroup("Group", [FloatParameter("Amount", 0.5)])
        let revision = group.structureRevision

        (group.get("Amount") as? FloatParameter)?.value = 1.0
        XCTAssertEqual(group.structureRevision, revision)

        group.append(FloatParameter("Other", 0.0))
        XCTAssertNotEqual(group.structureRevision, revision)
    }

    func testEnvironmentIntensityReachesTheParameterInUse() throws {
        let material = StandardMaterial(context: context)
        material.environmentIntensity = 0.5
        XCTAssertEqual(material.environmentIntensity, 0.5)

        // Replaced by another parameter of the same name: later writes reach the new one.
        let original = try XCTUnwrap(material.parameters.get("Environment Intensity"))
        material.parameters.remove(original)
        material.parameters.append(FloatParameter("Environment Intensity", 0.0))
        material.environmentIntensity = 0.75

        XCTAssertEqual(material.environmentIntensity, 0.75)
        XCTAssertEqual((original as? FloatParameter)?.value, 0.5, "the removed parameter is no longer written")
    }

    func testTexcoordTransformsReachTheParameterInUse() throws {
        let material = StandardMaterial(context: context)
        let transform = simd_float4x4(diagonal: [2, 2, 1, 1])
        material.setTexcoordTransform(transform, type: .reflection)

        let parameter = try XCTUnwrap(material.parameters.get(PBRTextureType.reflection.texcoordParameterName) as? Float4x4Parameter)
        XCTAssertEqual(parameter.value, transform)

        material.parameters.remove(parameter)
        material.setTexcoordTransform(matrix_identity_float4x4, type: .reflection)
        let replacement = try XCTUnwrap(material.parameters.get(PBRTextureType.reflection.texcoordParameterName) as? Float4x4Parameter)
        XCTAssertFalse(replacement === parameter)
        XCTAssertEqual(replacement.value, matrix_identity_float4x4)
    }
}
