import XCTest
@testable import QuotaCore

final class RefreshScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)
    func testFocusDefaultsToTenMinutes() {
        var schedule = RefreshSchedule()
        schedule.startWatching(at: start)
        XCTAssertEqual(schedule.secondsRemaining(at: start), 600)
        var refreshTimes: [Int] = []
        for second in 0...600 {
            if schedule.takeDueRefresh(at: start.addingTimeInterval(Double(second)), requestInFlight: false) { refreshTimes.append(second) }
        }
        XCTAssertEqual(refreshTimes, Array(stride(from: 0, to: 600, by: 10)))
        XCTAssertNil(schedule.watchingUntil)
        XCTAssertFalse(schedule.takeDueRefresh(at: start.addingTimeInterval(659), requestInFlight: false))
        XCTAssertTrue(schedule.takeDueRefresh(at: start.addingTimeInterval(660), requestInFlight: false))
    }
    func testConfiguredDurationsExpireAndRestartUsesNewChoice() {
        for minutes in [1, 5, 10, 30] {
            var schedule = RefreshSchedule()
            schedule.startWatching(at: start, durationMinutes: minutes)
            XCTAssertEqual(schedule.secondsRemaining(at: start), minutes * 60)
            XCTAssertTrue(schedule.takeDueRefresh(at: start, requestInFlight: false))
            let end = start.addingTimeInterval(Double(minutes * 60))
            XCTAssertFalse(schedule.takeDueRefresh(at: end, requestInFlight: false))
            XCTAssertNil(schedule.watchingUntil)
            XCTAssertEqual(schedule.nextRefreshAt, end.addingTimeInterval(60))
            schedule.startWatching(at: end, durationMinutes: 5)
            XCTAssertEqual(schedule.secondsRemaining(at: end), 300)
        }
    }
    func testManualStopAndRestart() {
        var schedule = RefreshSchedule()
        schedule.startWatching(at: start)
        schedule.stopWatching(at: start.addingTimeInterval(7))
        XCTAssertEqual(schedule.secondsRemaining(at: start.addingTimeInterval(8)), 0)
        XCTAssertFalse(schedule.takeDueRefresh(at: start.addingTimeInterval(10), requestInFlight: false))
        schedule.startWatching(at: start.addingTimeInterval(11))
        XCTAssertEqual(schedule.secondsRemaining(at: start.addingTimeInterval(11)), 600)
        XCTAssertTrue(schedule.takeDueRefresh(at: start.addingTimeInterval(11), requestInFlight: false))
    }
    func testProvidersRemainIndependent() {
        var codex = RefreshSchedule(), cursor = RefreshSchedule()
        codex.recordRefresh(at: start); cursor.recordRefresh(at: start)
        codex.startWatching(at: start.addingTimeInterval(2))
        XCTAssertTrue(codex.takeDueRefresh(at: start.addingTimeInterval(2), requestInFlight: false))
        XCTAssertFalse(cursor.takeDueRefresh(at: start.addingTimeInterval(2), requestInFlight: false))
        cursor.startWatching(at: start.addingTimeInterval(5))
        codex.stopWatching(at: start.addingTimeInterval(8))
        XCTAssertEqual(cursor.secondsRemaining(at: start.addingTimeInterval(8)), 597)
    }
    func testBusyRequestsAreSkippedWithoutCatchUpBurst() {
        var schedule = RefreshSchedule()
        schedule.startWatching(at: start)
        XCTAssertTrue(schedule.takeDueRefresh(at: start, requestInFlight: false))
        XCTAssertFalse(schedule.takeDueRefresh(at: start.addingTimeInterval(10), requestInFlight: true))
        XCTAssertFalse(schedule.takeDueRefresh(at: start.addingTimeInterval(11), requestInFlight: false))
        XCTAssertTrue(schedule.takeDueRefresh(at: start.addingTimeInterval(20), requestInFlight: false))
    }
    func testSleepExpiresFocusWithoutBurstAndManualRefreshResumesNormalCadence() {
        var schedule = RefreshSchedule()
        schedule.startWatching(at: start)
        XCTAssertFalse(schedule.takeDueRefresh(at: start.addingTimeInterval(900), requestInFlight: false))
        XCTAssertNil(schedule.watchingUntil)
        schedule.recordRefresh(at: start.addingTimeInterval(900))
        XCTAssertEqual(schedule.nextRefreshAt, start.addingTimeInterval(960))
    }

    func testGlobalStartAndStopShareDeadlineWithoutOverlappingBusyProviders() {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        var schedules = Array(repeating: RefreshSchedule(), count: 4)
        for index in schedules.indices { schedules[index].startWatching(at: time, durationMinutes: 10) }
        XCTAssertEqual(Set(schedules.compactMap(\.watchingUntil)).count, 1)
        for index in schedules.indices {
            XCTAssertEqual(schedules[index].takeDueRefresh(at: time, requestInFlight: index == 2), index != 2)
            XCTAssertEqual(schedules[index].nextRefreshAt, time.addingTimeInterval(10))
            schedules[index].stopWatching(at: time.addingTimeInterval(25))
            XCTAssertEqual(schedules[index].secondsRemaining(at: time.addingTimeInterval(25)), 0)
            XCTAssertEqual(schedules[index].nextRefreshAt, time.addingTimeInterval(85))
        }
    }
}
