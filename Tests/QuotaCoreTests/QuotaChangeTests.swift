import XCTest
@testable import QuotaCore

final class QuotaChangeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)
    private func snapshot(_ remaining: Double, at seconds: Double, id: String = "primary", title: String = "5 小时额度") -> QuotaSnapshot {
        QuotaSnapshot(windows: [QuotaWindow(id: id, title: title, usedPercent: 100 - remaining)], updatedAt: start.addingTimeInterval(seconds))
    }
    func testFirstLoadUnchangedAndInvisibleFractionsAreSilent() {
        var tracker = QuotaChangeTracker()
        XCTAssertNil(tracker.accept(snapshot(80, at: 0)))
        XCTAssertNil(tracker.accept(snapshot(80, at: 10)))
        XCTAssertNil(tracker.accept(snapshot(79.8, at: 20)))
        XCTAssertEqual(tracker.accept(snapshot(79.4, at: 30))?.dominantDelta, -1)
    }
    func testMagnitudeTiersAndDirections() {
        var tracker = QuotaChangeTracker()
        _ = tracker.accept(snapshot(90, at: 0))
        XCTAssertEqual(tracker.accept(snapshot(88, at: 10))?.intensity, .small)
        XCTAssertEqual(tracker.accept(snapshot(85, at: 20))?.intensity, .large)
        XCTAssertEqual(tracker.accept(snapshot(65, at: 30))?.intensity, .major)
        let reset = tracker.accept(snapshot(100, at: 40))
        XCTAssertEqual(reset?.dominantDelta, 35)
        XCTAssertEqual(reset?.intensity, .major)
    }
    func testStaleReconnectEstablishesNewBaseline() {
        var tracker = QuotaChangeTracker()
        _ = tracker.accept(snapshot(90, at: 0))
        XCTAssertNil(tracker.accept(snapshot(30, at: 151)))
        XCTAssertEqual(tracker.accept(snapshot(29, at: 161))?.dominantDelta, -1)
    }
    func testChangedBucketAndMissingWindowsDoNotGenerateFalseChange() {
        var tracker = QuotaChangeTracker()
        _ = tracker.accept(snapshot(5, at: 0))
        XCTAssertNil(tracker.accept(snapshot(100, at: 10, title: "每周额度")))
        XCTAssertNil(tracker.accept(QuotaSnapshot(windows: [], updatedAt: start.addingTimeInterval(20))))
        XCTAssertNil(tracker.accept(snapshot(70, at: 30, title: "每周额度")))
    }
    func testSimultaneousChangesSelectStrongestAndDeduplicate() {
        var tracker = QuotaChangeTracker()
        let old = QuotaSnapshot(windows: [QuotaWindow(id: "a", title: "a", usedPercent: 10), QuotaWindow(id: "b", title: "b", usedPercent: 10)], updatedAt: start)
        let new = QuotaSnapshot(windows: [QuotaWindow(id: "a", title: "a", usedPercent: 12), QuotaWindow(id: "b", title: "b", usedPercent: 35)], updatedAt: start.addingTimeInterval(10))
        _ = tracker.accept(old)
        let change = tracker.accept(new)
        XCTAssertEqual(change?.deltas, ["a": -2, "b": -25])
        XCTAssertEqual(change?.dominantDelta, -25)
        XCTAssertNil(tracker.accept(new))
    }
    func testProvidersHaveIndependentBaselines() {
        var codex = QuotaChangeTracker(), cursor = QuotaChangeTracker()
        _ = codex.accept(snapshot(80, at: 0))
        XCTAssertNil(cursor.accept(snapshot(20, at: 10)))
        XCTAssertEqual(codex.accept(snapshot(75, at: 10))?.dominantDelta, -5)
    }
}
