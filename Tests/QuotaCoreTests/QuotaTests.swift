import XCTest
@testable import QuotaCore

final class QuotaTests: XCTestCase {
    func testCodexPrefersNamedPoolAndUsesServerWindows() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":14,"windowDurationMins":10080}}}}"#.utf8)
        let result = try QuotaParser.codex(data)
        XCTAssertEqual(result.windows.map(\.remaining), [75, 86])
        XCTAssertEqual(result.windows.map(\.title), ["5 小时额度", "每周额度"])
        XCTAssertEqual(result.windows[0].resetsAt, Date(timeIntervalSince1970: 1800000000))
    }
    func testMissingCodexDataDoesNotBecomeZeroUsage() {
        XCTAssertThrowsError(try QuotaParser.codex(Data(#"{"rateLimits":null}"#.utf8)))
    }
    func testOverLimitClampsRemainingAndDoesNotHideZero() throws {
        let result = try QuotaParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":120},"secondary":{"usedPercent":0}}}"#.utf8))
        XCTAssertEqual(result.windows.map(\.remaining), [0, 100])
    }
    func testCursorSummaryPreservesPercentUnitsAndBillingReset() throws {
        let result = try QuotaParser.cursorSummary(Data(#"{"individualUsage":{"plan":{"autoPercentUsed":0.36,"apiPercentUsed":46.2}},"billingCycleEnd":"2026-10-05T00:00:00.000Z"}"#.utf8))
        XCTAssertEqual(result.windows[0].remaining, 99.64, accuracy: 0.001)
        XCTAssertEqual(result.windows[1].remaining, 53.8, accuracy: 0.001)
        XCTAssertEqual(result.windows.map(\.id), ["Cursor Models", "Other Models"])
        XCTAssertEqual(result.windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-10-05T00:00:00Z"))
    }
    func testCursorSummaryRejectsMissingPoolsAndInvalidData() {
        for value in [#"{}"#, #"{"individualUsage":{"plan":{"autoPercentUsed":10}}}"#, #"{"individualUsage":{"plan":{"autoPercentUsed":-1,"apiPercentUsed":20}}}"#, "<html>Sign in</html>"] {
            XCTAssertThrowsError(try QuotaParser.cursorSummary(Data(value.utf8)))
        }
    }
    func testCursorPageSyntheticLayout() throws {
        let result = try QuotaParser.cursor("Spending CURRENT PLAN Pro+ $60/mo Usage limits reset on Jan 15 ( 12 days left ) UPGRADE AVAILABLE Ultra $200/mo Cursor Models · Includes Cursor Grok and Composer 13 % used Additional usage beyond limits consumes Other Models quota or on-demand spend. Other Models 31 % used Additional usage beyond limits consumes on-demand spend. Weekly usage 0% used On-Demand $0.00 / $200")
        XCTAssertEqual(result.windows.map(\.remaining), [87, 69])
        XCTAssertEqual(result.resetNote, "Jan 15 ( 12 days left )")
    }
    func testCursorMissingPercentageCannotBorrowOtherPool() {
        XCTAssertThrowsError(try QuotaParser.cursor("Cursor Models unavailable Other Models 31% used On-Demand 0% used"))
        XCTAssertThrowsError(try QuotaParser.cursor("Cursor Models 13% used Other Models unavailable On-Demand 0% used"))
        XCTAssertThrowsError(try QuotaParser.cursor("Sign in to Cursor"))
    }
    func testStalenessIncludesResetAndCacheAge() {
        let now = Date(timeIntervalSince1970: 10000)
        XCTAssertFalse(QuotaSnapshot(windows: [], updatedAt: now).isStale(at: now))
        XCTAssertTrue(QuotaSnapshot(windows: [], updatedAt: now.addingTimeInterval(-151)).isStale(at: now))
        XCTAssertTrue(QuotaSnapshot(windows: [QuotaWindow(id: "a", title: "a", usedPercent: 50, resetsAt: now)], updatedAt: now).isStale(at: now))
    }
    func testSnapshotCacheRoundTripPreservesTimestamp() throws {
        let value = QuotaSnapshot(windows: [QuotaWindow(id: "a", title: "a", usedPercent: 23.5)], updatedAt: Date(timeIntervalSince1970: 1000), resetNote: "Jan 15")
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(value)), value)
    }
    func testCycleStartMetadataIsPreservedWithoutGuessingCalendarMonths() throws {
        let cursor = try QuotaParser.cursorSummary(Data(#"{"individualUsage":{"plan":{"autoPercentUsed":12,"apiPercentUsed":20}},"billingCycleStart":"2026-02-05T08:00:00Z","billingCycleEnd":"2026-03-05T08:00:00Z"}"#.utf8))
        XCTAssertEqual(cursor.windows[0].resetsAt!.timeIntervalSince(cursor.windows[0].cycleStartedAt!), 28 * 86400)
        let noStart = try QuotaParser.cursorSummary(Data(#"{"individualUsage":{"plan":{"autoPercentUsed":12,"apiPercentUsed":20}},"billingCycleEnd":"2026-03-05T08:00:00Z"}"#.utf8))
        XCTAssertNil(noStart.windows[0].cycleStartedAt)
        let codex = try QuotaParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1800018000}}}"#.utf8))
        XCTAssertEqual(codex.windows[0].cycleStartedAt, Date(timeIntervalSince1970: 1800000000))
    }

}
