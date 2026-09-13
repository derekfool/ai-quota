import XCTest
@testable import QuotaCore

final class ClaudeQuotaTests: XCTestCase {
    func testSessionWeeklyAndOptionalModelWindows() throws {
        let data = Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-09-10T20:00:00.000Z"},"seven_day":{"utilization":60,"resets_at":"2026-09-15T20:00:00Z"},"seven_day_sonnet":null,"seven_day_opus":{"utilization":0,"resets_at":null}}"#.utf8)
        let snapshot = try QuotaParser.claude(data)
        XCTAssertEqual(snapshot.windows.map(\.id), ["five_hour", "seven_day", "seven_day_opus"])
        XCTAssertEqual(snapshot.windows.map(\.remaining), [87.5,40,100])
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.windows[2].resetsAt)
    }
    func testMissingWindowIsNotFullQuotaAndOverageClamps() throws {
        let snapshot = try QuotaParser.claude(Data(#"{"five_hour":null,"seven_day":{"utilization":105}}"#.utf8))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].remaining, 0)
        XCTAssertEqual(snapshot.windows[0].title, "每周额度")
    }
    func testInvalidOrEmptyDataIsRejected() {
        for body in ["{}", "[]", "<html>Login</html>", #"{"five_hour":{"utilization":-1}}"#, #"{"five_hour":{"utilization":"12"}}"#, #"{"five_hour":{"utilization":true}}"#, #"{"five_hour":{"utilization":1,"resets_at":"tomorrow"}}"#] {
            XCTAssertThrowsError(try QuotaParser.claude(Data(body.utf8)), body)
        }
    }
    func testAddingClaudeDoesNotConsumeOtherProvidersSchedule() {
        let now = Date()
        var codex = RefreshSchedule(), cursor = RefreshSchedule(), claude = RefreshSchedule()
        codex.recordRefresh(at: now); cursor.recordRefresh(at: now)
        claude.startWatching(at: now)
        XCTAssertTrue(claude.takeDueRefresh(at: now, requestInFlight: false))
        XCTAssertFalse(codex.takeDueRefresh(at: now, requestInFlight: false))
        XCTAssertFalse(cursor.takeDueRefresh(at: now, requestInFlight: false))
    }
}
