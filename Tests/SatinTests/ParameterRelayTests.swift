import Combine
import Satin
import XCTest

/// A GenericParameter tells its groups and owners directly, and its publisher still sends every change.
final class ParameterRelayTests: XCTestCase {
    func testAValueChangeInvalidatesItsGroupWithoutAPublisherSubscription() {
        let amount = FloatParameter("Amount", 0)
        let group = ParameterGroup("Group", [amount])
        let revision = group.contentRevision
        amount.value = 1
        XCTAssertGreaterThan(group.contentRevision, revision)
    }

    func testAMinOrMaxChangeInvalidatesItsGroup() {
        let amount = FloatParameter("Amount", 0.5, 0, 1)
        let group = ParameterGroup("Group", [amount])
        var revision = group.contentRevision
        amount.min = -1
        XCTAssertGreaterThan(group.contentRevision, revision)
        revision = group.contentRevision
        amount.max = 2
        XCTAssertGreaterThan(group.contentRevision, revision)
    }

    func testADecodedGroupIsInvalidatedByItsParameters() throws {
        let group = ParameterGroup("Group", [FloatParameter("Amount", 0)])
        let decoded = try JSONDecoder().decode(ParameterGroup.self, from: JSONEncoder().encode(group))
        let amount = try XCTUnwrap(decoded.get("Amount", as: FloatParameter.self))
        let revision = decoded.contentRevision
        amount.value = 1
        XCTAssertGreaterThan(decoded.contentRevision, revision)
    }

    func testARemovedOrClearedParameterNoLongerInvalidatesTheGroup() {
        let removed = FloatParameter("Removed", 0)
        let cleared = FloatParameter("Cleared", 0)
        let group = ParameterGroup("Group", [removed, cleared])
        group.remove(removed)
        var revision = group.contentRevision
        removed.value = 1
        XCTAssertEqual(group.contentRevision, revision)
        group.clear()
        revision = group.contentRevision
        cleared.value = 1
        XCTAssertEqual(group.contentRevision, revision)
    }

    func testAParameterOutlivesItsGroup() {
        let amount = FloatParameter("Amount", 0)
        do { _ = ParameterGroup("Group", [amount]) }
        amount.value = 1
        XCTAssertEqual(amount.value, 1)
    }

    func testOwnersAreCalledBeforeThePublisherAndStopWhenAsked() {
        let amount = FloatParameter("Amount", 0)
        let first = NSObject()
        let second = NSObject()
        var calls: [String] = []
        amount.observeValueChanges(by: first) { calls.append("first \(amount.value)") }
        amount.observeValueChanges(by: second) { calls.append("second \(amount.value)") }
        let subscription = amount.valuePublisher.sink { calls.append("publisher \($0)") }
        defer { subscription.cancel() }

        amount.value = 1
        XCTAssertEqual(calls, ["first 1.0", "second 1.0", "publisher 1.0"])

        calls.removeAll()
        amount.stopObservingValueChanges(by: first)
        amount.value = 2
        XCTAssertEqual(calls, ["second 2.0", "publisher 2.0"])

        calls.removeAll()
        amount.value = 2
        XCTAssertEqual(calls, [])
    }

    func testObservingAgainReplacesTheOwnersHandler() {
        let amount = FloatParameter("Amount", 0)
        let owner = NSObject()
        var calls: [String] = []
        amount.observeValueChanges(by: owner) { calls.append("old") }
        amount.observeValueChanges(by: owner) { calls.append("new") }
        amount.value = 1
        XCTAssertEqual(calls, ["new"])
    }
}
