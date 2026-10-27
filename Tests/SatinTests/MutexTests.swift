//
//  MutexTests.swift
//  Satin
//
//  Created by Reza Ali on 10/13/24.
//

@preconcurrency import Satin
#if SWIFT_PACKAGE
import SatinCore
#endif

import simd
import XCTest

// Each iteration runs its work directly on concurrentPerform's threads: wrapping it in Tasks
// nothing awaits left millions of them mutating objects after the tests returned.
final class MutexTests: XCTestCase {
    let iterationCount = 100000

    private func makeContext() -> Context? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    // 0.244 sec
    func testDispatchQueue() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
        let queue = DispatchQueue(label: "ObjectQueue", attributes: .concurrent)

        measure {
            DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
                let newObject = Object(context: context)

                queue.sync(flags: .barrier) {
                    object.add(newObject)
                }

                queue.sync(flags: .barrier) {
                    object.remove(newObject)
                }

                queue.sync(flags: .barrier) {
                    object.removeAll()
                }
            }
        }
    }

    // 0.236 sec
    func testNSLock() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
        let lock = NSLock()

        measure {
            DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
                let newObject = Object(context: context)

                lock.lock()
                object.add(newObject)
                lock.unlock()

                lock.lock()
                object.remove(newObject)
                lock.unlock()

                lock.lock()
                object.removeAll()
                lock.unlock()
            }
        }
    }

    // 0.251 sec
    func testNSRecursiveLock() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
        let lock = NSRecursiveLock()

        measure {
            DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
                let newObject = Object(context: context)

                lock.lock()
                object.add(newObject)
                lock.unlock()

                lock.lock()
                object.remove(newObject)
                lock.unlock()

                lock.lock()
                object.removeAll()
                lock.unlock()
            }
        }
    }

    // 0.244 sec
    func testPThreadMutex() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
        let mutex = PThreadMutex(type: .normal)

        measure {
            DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
                let newObject = Object(context: context)

                mutex.unbalancedLock()
                object.add(newObject)
                mutex.unbalancedUnlock()

                mutex.unbalancedLock()
                object.remove(newObject)
                mutex.unbalancedUnlock()

                mutex.unbalancedLock()
                object.removeAll()
                mutex.unbalancedUnlock()
            }
        }
    }

    // 0.250 sec
    func testUnfairLock() throws {
        guard let context = makeContext() else { return }
        let object = Object(context: context)
        let unfairLock = UnfairLock()

        measure {
            DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
                let newObject = Object(context: context)

                unfairLock.unbalancedLock()
                object.add(newObject)
                unfairLock.unbalancedUnlock()

                unfairLock.unbalancedLock()
                object.remove(newObject)
                unfairLock.unbalancedUnlock()

                unfairLock.unbalancedLock()
                object.removeAll()
                unfairLock.unbalancedUnlock()
            }
        }
    }
}
