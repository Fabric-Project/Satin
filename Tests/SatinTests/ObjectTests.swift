//
//  ObjectTests.swift
//
//
//  Created by Taylor Holliday on 3/23/22.
//

import Satin
#if SWIFT_PACKAGE
import SatinCore
#endif

import simd
import XCTest

final class ObjectTests: XCTestCase {
    private func makeContext() -> Context? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    func testObjectConcurrency() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
//        let lock = NSLock()
//        let mutex = PThreadMutex(type: .normal)
//        let queue = DispatchQueue(label: "ObjectQueue", attributes: .concurrent)

        let unfair = UnfairLock()
        let iterationCount = 100000

        // 0.270 s w/ NSRecursiveLock
        // 0.252 w/ NSLock
        // 0.241 w/ DispatchQueue
        // 0.246 w/ PThreadMutex
        // 0.244 w/ Unfair
        measure {
            DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
                let newObject = Object(context: context)

//                Task {
//                    lock.lock()
//                    object.add(newObject)
//                    lock.unlock()
//                }
//
//                Task {
//                    lock.lock()
//                    object.remove(newObject)
//                    lock.unlock()
//                }
//
//                Task {
//                    lock.lock()
//                    object.removeAll()
//                    lock.unlock()
//                }

//                Task {
//                    queue.sync(flags: .barrier) {
//                        object.add(newObject)
//                    }
//                }
//
//                Task {
//                    queue.sync(flags: .barrier) {
//                        object.remove(newObject)
//                    }
//                }
//
//                Task {
//                    queue.sync(flags: .barrier) {
//                        object.removeAll()
//                    }
//                }

//                Task {
//                    mutex.sync {
//                        object.add(newObject)
//                    }
//                }
//
//                Task {
//                    mutex.sync {
//                        object.remove(newObject)
//                    }
//                }
//
//                Task {
//                    mutex.sync {
//                        object.removeAll()
//                    }
//                }

                // Run here, on concurrentPerform's threads, rather than in Tasks nothing awaits:
                // those outlived the test and kept mutating objects (and the transform epoch)
                // while later tests ran.
                unfair.sync {
                    object.add(newObject)
                }

                unfair.sync {
                    object.remove(newObject)
                }

                unfair.sync {
                    object.removeAll()
                }
            }
        }
    }

    func testObjectLocalTransforms() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)

        XCTAssertTrue(simd_equal(object.localMatrix, matrix_identity_float4x4))

        // Ensure matrix updates after changing position.
        object.position = .init(1, 2, 3)
        XCTAssertTrue(simd_equal(object.localMatrix, translationMatrix3f(object.position)))
        object.position = .zero

        object.scale = .init(1, 2, 3)
        XCTAssertTrue(simd_equal(object.localMatrix, scaleMatrix3f(object.scale)))
        object.scale = .init(1, 1, 1)
    }

    func testObjectWorldTransforms() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
        let child = Object(context: context)
        object.add(child)
        object.position = .init(1, 2, 3)

        XCTAssert(simd_equal(child.localMatrix, matrix_identity_float4x4))
        XCTAssert(simd_equal(child.worldMatrix, translationMatrix3f(object.position)))
    }

    func testAddRemoveChild() {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
        let child = Object(context: context)

        XCTAssertEqual(object.children.count, 0)
        object.add(child)
        XCTAssertEqual(object.children.count, 1)
        object.remove(child)
        XCTAssertEqual(object.children.count, 0)
    }

    func testLocalBounds() {
        guard let context = makeContext() else { return }
        let mesh = Mesh(
            context: context,
            geometry: SphereGeometry(context: context),
            material: nil
        )
        XCTAssert(
            mesh.localBounds.equals(
                Bounds(
                    min: .init(-1, -1, -1),
                    max: .init(1, 1, 1)
                )
            )
        )
    }

    func testMirroredWorldTransformKeepsItsHandedness() throws {
        guard let context = makeContext() else { return }
        let parent = Object(context: context)
        // Equal magnitudes, so the rotated child has no shear to lose.
        parent.scale = [2, -2, 2]
        let child = Object(context: context)
        child.orientation = simd_quatf(angle: 0.6, axis: simd_normalize([1, 2, 3]))
        parent.add(child)

        XCTAssertLessThan(child.worldScale.x, 0, "Mirroring shows as a negative x scale")
        XCTAssertEqual(simd_length(child.worldOrientation.vector), 1, accuracy: 1e-5)
        let rebuilt = simd_float4x4(translation: child.worldPosition, rotation: child.worldOrientation, scale: child.worldScale)
        for column in 0 ..< 4 {
            XCTAssertEqual(simd_distance(rebuilt[column], child.worldMatrix[column]), 0, accuracy: 1e-5, "column \(column)")
        }
    }

    func testZeroWorldScaleKeepsAUnitOrientation() throws {
        guard let context = makeContext() else { return }
        let parent = Object(context: context)
        let turn = simd_quatf(angle: 0.6, axis: [0, 0, 1])
        parent.orientation = turn
        let child = Object(context: context)
        child.scale = [0, 1, 1]
        parent.add(child)

        XCTAssertEqual(child.worldScale.x, 0)
        XCTAssertEqual(simd_length(child.worldOrientation.vector), 1, accuracy: 1e-5, "No division by the zero scale")
        XCTAssertEqual(simd_distance(child.worldOrientation.act([1, 0, 0]), turn.act([1, 0, 0])), 0, accuracy: 1e-5, "The collapsed axis keeps the parent's direction")
    }

    private func isFinite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].allSatisfy { column in
            column.x.isFinite && column.y.isFinite && column.z.isFinite && column.w.isFinite
        }
    }

    func testLookingAlongTheUpDirectionGivesAnOrthonormalTransform() throws {
        guard let context = makeContext() else { return }
        for target: simd_float3 in [[0, 0, 0], [0, 10, 0]] {
            let object = Object(context: context)
            object.position = [0, 5, 0]
            object.lookAt(target: target)
            let matrix = object.localMatrix
            XCTAssertTrue(isFinite(matrix), "looking at \(target) along the up direction")
            let axes = [matrix.columns.0, matrix.columns.1, matrix.columns.2].map { simd_make_float3($0) }
            for axis in axes { XCTAssertEqual(simd_length(axis), 1, accuracy: 1e-5) }
            XCTAssertEqual(simd_dot(axes[0], axes[1]), 0, accuracy: 1e-5)
            XCTAssertEqual(simd_dot(axes[1], axes[2]), 0, accuracy: 1e-5)
            XCTAssertEqual(simd_distance(axes[2], simd_normalize(target - object.position)), 0, accuracy: 1e-5, "it still faces the target")
        }
    }

    func testACameraLookingStraightDownStaysFinite() throws {
        guard let context = makeContext() else { return }
        let camera = PerspectiveCamera(context: context, position: [0, 5, 0], near: 0.1, far: 100, fov: 30)
        camera.lookAt(target: .zero)
        XCTAssertTrue(isFinite(camera.viewProjectionMatrix))
        // A camera's z axis points away from what it sees.
        XCTAssertEqual(simd_distance(camera.worldForwardDirection, [0, 1, 0]), 0, accuracy: 1e-5, "it faces the target")
    }

    func testLightsAimedStraightDownCastFiniteShadows() throws {
        guard let context = makeContext() else { return }
        let spotLight = SpotLight(context: context, color: [1, 1, 1])
        let directionalLight = DirectionalLight(context: context, color: [1, 1, 1])
        for light: Light in [spotLight, directionalLight] {
            light.castShadow = true
            light.position = [0, 5, 0]
            light.lookAt(target: .zero)
            light.shadow.update(light: light)
            XCTAssertTrue(isFinite(light.shadow.camera.viewProjectionMatrix), "\(light.label)'s shadow camera")
        }
        XCTAssertTrue(isFinite(spotLight.projectorMatrix), "the spotlight's projector")
    }
}
