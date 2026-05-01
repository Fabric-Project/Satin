import Satin
import XCTest

final class ParameterTests: XCTestCase {
    func testMaterialSetUpdatesExistingParameterWithoutDuplicatingIt() {
        let material = BasicColorMaterial()

        material.set("Exposure", 0.5)
        material.set("Exposure", 1.25)

        let parameter = material.get("Exposure", as: FloatParameter.self)
        XCTAssertNotNil(parameter)
        XCTAssertEqual(parameter?.value, 1.25)
        XCTAssertEqual(material.parameters.params.filter { $0.label == "Exposure" }.count, 1)
    }

    func testSetParametersClonesIncomingGroup() {
        let material = BasicColorMaterial()
        let incoming = ParameterGroup("Incoming", [
            FloatParameter("Amount", 0.25),
            BoolParameter("Enabled", true),
        ])

        material.setParameters(from: incoming)

        let amount = material.get("Amount", as: FloatParameter.self)
        let enabled = material.get("Enabled", as: BoolParameter.self)
        XCTAssertEqual(amount?.value, 0.25)
        XCTAssertEqual(enabled?.value, true)

        (incoming.get("Amount", as: FloatParameter.self))?.value = 0.9
        (incoming.get("Enabled", as: BoolParameter.self))?.value = false

        XCTAssertEqual(material.get("Amount", as: FloatParameter.self)?.value, 0.25)
        XCTAssertEqual(material.get("Enabled", as: BoolParameter.self)?.value, true)
    }

    func testParameterGroupSetValuesFromUpdatesOnlySharedKeys() {
        let base = ParameterGroup("Base", [
            FloatParameter("Shared", 0.1),
            IntParameter("OnlyBase", 2),
        ])

        let incoming = ParameterGroup("Incoming", [
            FloatParameter("Shared", 0.75),
            BoolParameter("OnlyIncoming", true),
        ])

        base.setValuesFrom(incoming)

        XCTAssertEqual(base.get("Shared", as: FloatParameter.self)?.value, 0.75)
        XCTAssertEqual(base.get("OnlyBase", as: IntParameter.self)?.value, 2)
        XCTAssertNil(base.get("OnlyIncoming"))
    }
}
