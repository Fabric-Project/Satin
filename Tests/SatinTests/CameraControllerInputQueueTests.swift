@testable import Satin
import XCTest

/// Camera controller input is appended on the main thread and taken on whichever thread updates
/// the camera. Run under Thread Sanitizer for the concurrent test to mean anything.
final class CameraControllerInputQueueTests: XCTestCase {
    func testTakeReturnsEverythingAppendedInOrderAndEmptiesTheQueue() {
        let queue = CameraControllerInputQueue<Int>()
        for value in 0 ..< 10 { queue.append(value) }

        var inputs = ContiguousArray<Int>()
        queue.take(into: &inputs)
        XCTAssertEqual(Array(inputs), Array(0 ..< 10))

        inputs.removeAll(keepingCapacity: true)
        queue.take(into: &inputs)
        XCTAssertTrue(inputs.isEmpty)
    }

    func testInputAppendedOnAnotherThreadArrivesOnceAndInOrder() {
        let queue = CameraControllerInputQueue<Int>()
        let count = 10_000
        let appended = expectation(description: "all input appended")
        DispatchQueue.global().async {
            for value in 0 ..< count { queue.append(value) }
            appended.fulfill()
        }

        var received: [Int] = []
        var inputs = ContiguousArray<Int>()
        let deadline = Date().addingTimeInterval(10)
        while received.count < count, Date() < deadline {
            inputs.removeAll(keepingCapacity: true)
            queue.take(into: &inputs)
            received.append(contentsOf: inputs)
        }
        wait(for: [appended], timeout: 10)
        XCTAssertEqual(received, Array(0 ..< count))
    }
}
