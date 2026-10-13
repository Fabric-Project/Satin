import Metal
import Satin
import simd
import XCTest

/// Repeated encoding (one mesh drawn several times a frame): every iteration
/// draws exactly the pose and instance matrices it was updated with, even when they did not
/// change, and velocity compares each iteration with itself last frame, not with the
/// iteration before it.
final class RepeatedEncodingTests: XCTestCase {
    private let iterationCount = 5

    func testEachIterationDrawsItsOwnPoseWithItsOwnVelocity() throws {
        let palette = JointPalette(device: try device(), jointCount: 1, maxBuffersInFlight: 3)
        palette.prepareForRepeatedEncoding(count: iterationCount)
        let firstPoses = (0..<iterationCount).map { translation(x: Float($0)) }

        runFrame(palette, poses: firstPoses)
        for iteration in 0..<iterationCount {
            let joint = selectedJoint(palette, iteration: iteration)
            assertEqual(joint.current, firstPoses[iteration])
            assertEqual(joint.previous, firstPoses[iteration], "A first frame has no motion")
        }

        // The same layout again: still, though every iteration differs from its neighbour.
        runFrame(palette, poses: firstPoses)
        for iteration in 0..<iterationCount {
            assertEqual(selectedJoint(palette, iteration: iteration).previous, firstPoses[iteration], "Iteration \(iteration) did not move")
        }

        // Only iteration 2 moves.
        var secondPoses = firstPoses
        secondPoses[2] = translation(x: 10)
        runFrame(palette, poses: secondPoses)
        let moved = selectedJoint(palette, iteration: 2)
        assertEqual(moved.current, secondPoses[2])
        assertEqual(moved.previous, firstPoses[2])
        assertEqual(selectedJoint(palette, iteration: 3).previous, firstPoses[3])
    }

    func testUnchangedPoseIsDrawnByEveryIteration() throws {
        let palette = JointPalette(device: try device(), jointCount: 1, maxBuffersInFlight: 3)
        palette.prepareForRepeatedEncoding(count: 4)
        let pose = translation(x: 3)
        palette.reset(matrices: [pose])
        // No updates between iterations: each capture still records the pose.
        for iteration in 0..<4 { palette.captureRepeatedEncoding(iteration: iteration, count: 4) }
        for iteration in 0..<4 { assertEqual(selectedJoint(palette, iteration: iteration).current, pose) }
    }

    func testLargeIterationCountsStayInsideTheBuffer() throws {
        let palette = JointPalette(device: try device(), jointCount: 2, maxBuffersInFlight: 3)
        palette.prepareForRepeatedEncoding(count: 40)
        // Selected before any capture, and after captures for some iterations only.
        for iteration in [0, 39] {
            palette.selectRecentSlot(iteration: iteration, count: 40)
            XCTAssertGreaterThanOrEqual(palette.offset, 0)
            XCTAssertLessThanOrEqual(palette.offset + MemoryLayout<SkinJoint>.stride * 2, palette.buffer.length)
        }
        for iteration in 0..<10 { palette.captureRepeatedEncoding(iteration: iteration, count: 40) }
        for iteration in [0, 9, 10, 39] {
            palette.selectRecentSlot(iteration: iteration, count: 40)
            XCTAssertGreaterThanOrEqual(palette.offset, 0)
            XCTAssertLessThanOrEqual(palette.offset + MemoryLayout<SkinJoint>.stride * 2, palette.buffer.length)
        }
    }

    func testMeshForwardsRepeatedEncodingToItsGeometrysPalette() throws {
        let context = Context(device: try device(), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let geometry = Geometry(context: context)
        let mesh = Mesh(context: context, label: "Skinned", geometry: geometry, material: nil)
        mesh.prepareForRepeatedEncoding(count: 3)
        // Attached after preparing, as Fabric sends a new posed geometry at any time.
        let palette = JointPalette(device: context.device, jointCount: 1)
        geometry.jointPalette = palette
        let poses = (0..<3).map { translation(x: Float($0) + 1) }
        for iteration in 0..<3 {
            palette.update(matrices: [poses[iteration]])
            mesh.update()
            mesh.captureRepeatedEncodingState(iteration: iteration, count: 3)
        }
        for iteration in 0..<3 {
            mesh.selectRepeatedEncodingState(iteration: iteration, count: 3)
            assertEqual(joint(palette).current, poses[iteration])
        }
    }

    func testRepeatedInstancesReportVelocityPerIteration() throws {
        let context = Context(device: try device(), sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let instances = InstancedMesh(context: context, geometry: Geometry(context: context), material: nil, count: 1)
        instances.prepareForRepeatedEncoding(count: 3)
        func frame(_ offsets: [Float]) {
            for iteration in 0..<3 {
                instances.setMatrixAt(index: 0, matrix: translation(x: offsets[iteration]))
                instances.update()
                instances.captureRepeatedEncodingState(iteration: iteration, count: 3)
            }
        }
        frame([0, 1, 2])
        frame([0, 1, 2])
        for iteration in 0..<3 {
            let uniforms = try selectedInstance(instances, iteration: iteration)
            assertEqual(uniforms.modelMatrix, translation(x: Float(iteration)))
            assertEqual(uniforms.previousModelMatrix, uniforms.modelMatrix, "A still iteration reports no motion")
        }
        frame([0, 5, 2])
        assertEqual(try selectedInstance(instances, iteration: 1).previousModelMatrix, translation(x: 1))
        assertEqual(try selectedInstance(instances, iteration: 2).previousModelMatrix, translation(x: 2))
    }

    func testOneIterationNeverOverwritesAFrameInFlight() throws {
        let context = Context(device: try device(), sampleCount: 1, colorPixelFormat: .bgra8Unorm, maxBuffersInFlight: 3)
        let instances = InstancedMesh(context: context, geometry: Geometry(context: context), material: nil, count: 1)
        instances.prepareForRepeatedEncoding(count: 1)
        func frame(_ offset: Float) {
            instances.setMatrixAt(index: 0, matrix: translation(x: offset))
            instances.update()
            instances.captureRepeatedEncodingState(iteration: 0, count: 1)
        }
        frame(0)
        instances.selectRepeatedEncodingState(iteration: 0, count: 1)
        let firstFrameOffset = try XCTUnwrap(instances.instanceMatrixBuffer).offset
        // Two more frames in flight, each uploading on change and on capture.
        frame(1)
        frame(2)
        let buffer = try XCTUnwrap(instances.instanceMatrixBuffer)
        let firstFrame = buffer.buffer.contents().advanced(by: firstFrameOffset).assumingMemoryBound(to: InstanceMatrixUniforms.self).pointee
        assertEqual(firstFrame.modelMatrix, translation(x: 0), "Frame 0's slot is untouched while it may still be in flight")
    }

    func testPaletteSharedByTwoMeshesKeepsItsMotionHistory() throws {
        let palette = JointPalette(device: try device(), jointCount: 1, maxBuffersInFlight: 3)
        palette.prepareForRepeatedEncoding(count: 2)
        func frame(_ poses: [simd_float4x4]) {
            for (iteration, pose) in poses.enumerated() {
                palette.update(matrices: [pose])
                // Two meshes draw this palette: both capture every iteration.
                palette.captureRepeatedEncoding(iteration: iteration, count: 2)
                palette.captureRepeatedEncoding(iteration: iteration, count: 2)
            }
            // Drawing selects each iteration.
            for iteration in poses.indices { palette.selectRecentSlot(iteration: iteration, count: 2) }
        }
        frame([translation(x: 0), translation(x: 1)])
        frame([translation(x: 10), translation(x: 1)])
        palette.selectRecentSlot(iteration: 0, count: 2)
        let moved = joint(palette)
        assertEqual(moved.current, translation(x: 10))
        assertEqual(moved.previous, translation(x: 0), "The second capture must not erase last frame's pose")
        palette.selectRecentSlot(iteration: 1, count: 2)
        assertEqual(joint(palette).previous, translation(x: 1))
    }

    // MARK: - Helpers

    private func runFrame(_ palette: JointPalette, poses: [simd_float4x4]) {
        for (iteration, pose) in poses.enumerated() {
            palette.update(matrices: [pose])
            palette.captureRepeatedEncoding(iteration: iteration, count: poses.count)
        }
    }

    private func selectedJoint(_ palette: JointPalette, iteration: Int) -> SkinJoint {
        palette.selectRecentSlot(iteration: iteration, count: iterationCount)
        return joint(palette)
    }

    private func joint(_ palette: JointPalette) -> SkinJoint {
        palette.buffer.contents().advanced(by: palette.offset).assumingMemoryBound(to: SkinJoint.self).pointee
    }

    private func selectedInstance(_ instances: InstancedMesh, iteration: Int) throws -> InstanceMatrixUniforms {
        instances.selectRepeatedEncodingState(iteration: iteration, count: 3)
        let buffer = try XCTUnwrap(instances.instanceMatrixBuffer)
        return buffer.buffer.contents().advanced(by: buffer.offset).assumingMemoryBound(to: InstanceMatrixUniforms.self).pointee
    }

    private func device() throws -> MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func translation(x: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = simd_float4(x, 0, 0, 1)
        return matrix
    }

    private func assertEqual(_ actual: simd_float4x4, _ expected: simd_float4x4, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        for column in 0..<4 {
            for row in 0..<4 {
                XCTAssertEqual(actual[column][row], expected[column][row], accuracy: 1e-5, message, file: file, line: line)
            }
        }
    }
}
