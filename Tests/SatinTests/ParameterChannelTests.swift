import Combine
@testable import Satin
import XCTest

/// A parameter group owned by a render queue: the UI writes with `submit`, the owner applies the
/// latest value on its queue, and changes come back to the main thread through `mainValue` and
/// `mainValuePublisher`, coalesced. Without a queue everything stays synchronous, as before.
/// Run under Thread Sanitizer for the threading to mean anything.
final class ParameterChannelTests: XCTestCase {
    private var subscriptions = Set<AnyCancellable>()

    override func tearDown() {
        subscriptions.removeAll()
        super.tearDown()
    }

    /// Spins the main run loop until `condition` holds or `timeout` passes.
    private func spinMain(until condition: () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }

    // MARK: - P5: no queue, nothing changes

    func testWithoutAQueueSubmitSetsTheValueAndPublishesAtOnce() {
        let parameter = FloatParameter("Amount", 0, 0, 1, .slider)
        _ = ParameterGroup("Group", [parameter])
        var published: [Float] = []
        parameter.mainValuePublisher.sink { published.append($0) }.store(in: &subscriptions)

        parameter.submit(0.5)

        XCTAssertEqual(parameter.value, 0.5)
        XCTAssertEqual(parameter.mainValue, 0.5)
        XCTAssertEqual(published, [0.5])
    }

    // MARK: - P2: a flood of UI writes

    func testAFloodOfSubmitsAppliesOnlyTheLatestOnTheOwner() {
        let renderQueue = DispatchQueue(label: "Owner")
        let parameter = FloatParameter("Amount", 0, 0, 10000, .slider)
        let group = ParameterGroup("Group", [parameter])
        group.renderQueue = renderQueue

        var appliedValues: [Float] = []
        var appliedOnOwner = true
        let ownerKey = DispatchSpecificKey<Bool>()
        renderQueue.setSpecific(key: ownerKey, value: true)
        parameter.valuePublisher.sink { value in
            appliedValues.append(value)
            appliedOnOwner = appliedOnOwner && DispatchQueue.getSpecific(key: ownerKey) == true
        }.store(in: &subscriptions)

        renderQueue.suspend()
        for step in 1 ... 10000 { parameter.submit(Float(step)) }
        XCTAssertEqual(parameter.mainValue, 10000, "the UI sees its own latest value at once")
        renderQueue.resume()
        renderQueue.sync {}

        renderQueue.sync {
            XCTAssertEqual(parameter.value, 10000)
            XCTAssertEqual(appliedValues, [10000], "one application of the latest value")
            XCTAssertTrue(appliedOnOwner)
        }
    }

    // MARK: - P4: buttons keep every press

    func testButtonPressesAllArriveInOrder() {
        let renderQueue = DispatchQueue(label: "Owner")
        let button = BoolParameter("Fire", false, .button)
        let group = ParameterGroup("Group", [button])
        group.renderQueue = renderQueue

        var presses: [Bool] = []
        button.valuePublisher.sink { presses.append($0) }.store(in: &subscriptions)

        renderQueue.suspend()
        button.submit(true)
        button.submit(false)
        button.submit(true)
        button.submit(false)
        renderQueue.resume()
        renderQueue.sync {}

        renderQueue.sync { XCTAssertEqual(presses, [true, false, true, false]) }
    }

    // MARK: - P3: the owner drives the UI

    func testValuesSetOnTheOwnerReachTheMainThreadCoalesced() {
        let renderQueue = DispatchQueue(label: "Owner")
        let parameter = FloatParameter("Amount", 0, 0, 1000, .slider)
        let group = ParameterGroup("Group", [parameter])
        group.renderQueue = renderQueue

        var published: [Float] = []
        var publishedOnMain = true
        parameter.mainValuePublisher.sink { value in
            published.append(value)
            publishedOnMain = publishedOnMain && Thread.isMainThread
        }.store(in: &subscriptions)

        renderQueue.sync {
            for step in 1 ... 1000 { parameter.value = Float(step) }
        }
        spinMain(until: { parameter.mainValue == 1000 })

        XCTAssertEqual(parameter.mainValue, 1000)
        XCTAssertEqual(published.last, 1000)
        XCTAssertLessThanOrEqual(published.count, 2, "one main delivery per burst, latest value")
        XCTAssertTrue(publishedOnMain)
    }

    // MARK: - Echo: an older owner value never overwrites a newer slider position

    func testAnOlderOwnerValueDoesNotOverwriteANewerSubmit() {
        let renderQueue = DispatchQueue(label: "Owner")
        let parameter = FloatParameter("Amount", 0, 0, 10, .slider)
        let group = ParameterGroup("Group", [parameter])
        group.renderQueue = renderQueue

        // The owner changes the value; its publication to main is now queued behind this test.
        renderQueue.sync { parameter.value = 1 }
        // Before main hears of it, the slider moves on and the owner hasn't applied that yet.
        renderQueue.suspend()
        parameter.submit(2)

        spinMain(until: { false }, timeout: 0.1)
        XCTAssertEqual(parameter.mainValue, 2, "the stale owner value must not pull the slider back")

        renderQueue.resume()
        renderQueue.sync {}
        renderQueue.sync { XCTAssertEqual(parameter.value, 2) }
        spinMain(until: { false }, timeout: 0.1)
        XCTAssertEqual(parameter.mainValue, 2)
    }

    // MARK: - Min and max

    func testMinAndMaxSetOnTheOwnerReachTheMainThread() {
        let renderQueue = DispatchQueue(label: "Owner")
        let parameter = FloatParameter("Amount", 0.5, 0, 1, .slider)
        let group = ParameterGroup("Group", [parameter])
        group.renderQueue = renderQueue

        renderQueue.sync {
            parameter.min = -1
            parameter.max = 2
        }
        spinMain(until: { parameter.mainMax == 2 })

        XCTAssertEqual(parameter.mainMin, -1)
        XCTAssertEqual(parameter.mainMax, 2)
    }
}

extension ParameterChannelTests {
    /// A parameter shown in two groups owned by the same queue keeps one owner: each submit
    /// applies once, whichever group it was reached through.
    func testAParameterSharedByTwoGroupsOnOneQueueAppliesEachSubmitOnce() {
        let renderQueue = DispatchQueue(label: "Owner")
        let parameter = FloatParameter("Amount", 0, 0, 10, .slider)
        let first = ParameterGroup("First", [parameter])
        let second = ParameterGroup("Second", [parameter])
        first.renderQueue = renderQueue
        second.renderQueue = renderQueue

        var applied: [Float] = []
        var subscription: AnyCancellable? = parameter.valuePublisher.sink { applied.append($0) }
        renderQueue.suspend()
        parameter.submit(3)
        parameter.submit(4)
        renderQueue.resume()
        renderQueue.sync {}
        renderQueue.sync { XCTAssertEqual(applied, [4]) }
        subscription = nil
        _ = subscription
    }

    /// Removing a parameter doesn't end its ownership: its submits still apply on the owner.
    func testARemovedParameterStaysWithItsOwner() {
        let renderQueue = DispatchQueue(label: "Owner")
        let parameter = FloatParameter("Amount", 0, 0, 10, .slider)
        let group = ParameterGroup("Group", [parameter])
        group.renderQueue = renderQueue
        group.remove(parameter)

        parameter.submit(5)
        renderQueue.sync {}
        renderQueue.sync { XCTAssertEqual(parameter.value, 5) }
    }
}
