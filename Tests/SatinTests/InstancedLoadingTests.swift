import Metal
import Satin
import simd
import XCTest

/// Loading a model's meshes as instanced meshes, each where a plain load puts its mesh.
final class InstancedLoadingTests: XCTestCase {
    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    func testInstancedLoadingPlacesEachMeshAsPlainLoadingDoes() throws {
        let context = try makeContext()
        for name in ["animated_mover", "two_joint_bar"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "usda"))
            let plain = loadAnimatedAsset(url: url, context: context)
            let instanced = loadAnimatedAsset(url: url, context: context, instanced: true)
            plain.animation?.setTime(0.5)
            instanced.animation?.setTime(0.5)

            let plainMeshes = plain.root.getChildren().compactMap { $0 as? Mesh }
            let instancedMeshes = instanced.root.getChildren().compactMap { $0 as? InstancedMesh }
            XCTAssertEqual(instancedMeshes.count, plainMeshes.count, name)
            XCTAssertFalse(instancedMeshes.isEmpty, name)
            for (plainMesh, instancedMesh) in zip(plainMeshes, instancedMeshes) {
                assertEqual(instancedMesh.worldMatrix, plainMesh.worldMatrix)
                XCTAssertEqual(instancedMesh.geometry.isSkinned, plainMesh.geometry.isSkinned, name)
            }
        }
    }

    private func assertEqual(_ actual: simd_float4x4, _ expected: simd_float4x4, file: StaticString = #filePath, line: UInt = #line) {
        for column in 0 ..< 4 {
            XCTAssertEqual(simd_distance(actual[column], expected[column]), 0, accuracy: 1e-4, "column \(column)", file: file, line: line)
        }
    }
}
