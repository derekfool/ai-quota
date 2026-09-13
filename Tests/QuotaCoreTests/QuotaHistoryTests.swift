import XCTest
@testable import QuotaCore

final class QuotaHistoryTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func window(_ used: Double, cycle: Int = 0) -> QuotaWindow {
        QuotaWindow(id: "five", title: "5h", usedPercent: used,
            resetsAt: start.addingTimeInterval(Double(cycle + 1) * 18000),
            cycleStartedAt: start.addingTimeInterval(Double(cycle) * 18000))
    }
    func testFreshInstallationAndProviderIsolation() {
        var history = QuotaHistory()
        history.record(QuotaSnapshot(windows: [window(20)], updatedAt: start), provider: "codex")
        XCTAssertNil(history.summary(provider: "codex", window: window(20), at: start).consumedPoints)
        history.record(QuotaSnapshot(windows: [window(23)], updatedAt: start.addingTimeInterval(60)), provider: "codex")
        let result = history.summary(provider: "codex", window: window(23), at: start.addingTimeInterval(60))
        XCTAssertEqual(result.consumedPoints, 3)
        XCTAssertTrue(result.isPartial)
        XCTAssertNil(history.summary(provider: "claude", window: window(23), at: start).consumedPoints)
    }
    func testResetDoesNotSubtractUsageAndMarksUnobservedTail() {
        var history = QuotaHistory()
        history.record(QuotaSnapshot(windows: [window(75)], updatedAt: start.addingTimeInterval(17940)), provider: "codex")
        history.record(QuotaSnapshot(windows: [window(5, cycle: 1)], updatedAt: start.addingTimeInterval(18060)), provider: "codex")
        let summary = history.summary(provider: "codex", window: window(5), at: start.addingTimeInterval(18060))
        XCTAssertEqual(summary.consumedPoints, 5)
        XCTAssertTrue(summary.hasGaps)
        XCTAssertFalse(QuotaHistory.sameCycle(window(75), window(5, cycle: 1)))
    }
    func testRecoveryCorrectionIsNotAResetAndDuplicateSamplesIgnored() {
        var history = QuotaHistory()
        for (time, used) in [(0.0, 40.0), (60, 30), (120, 32)] {
            history.record(QuotaSnapshot(windows: [window(used)], updatedAt: start.addingTimeInterval(time)), provider: "cursor")
        }
        history.record(QuotaSnapshot(windows: [window(80)], updatedAt: start), provider: "cursor")
        let result = history.summary(provider: "cursor", window: window(32), at: start.addingTimeInterval(120))
        XCTAssertEqual(result.samples.count, 3)
        XCTAssertEqual(result.consumedPoints, 2)
        XCTAssertTrue(result.hasGaps)
    }
    func testPersistenceAndAccountReset() throws {
        var history = QuotaHistory()
        history.record(QuotaSnapshot(windows: [window(20)], updatedAt: start), provider: "claude")
        history.record(QuotaSnapshot(windows: [window(25)], updatedAt: start.addingTimeInterval(60)), provider: "claude")
        var restored = try JSONDecoder().decode(QuotaHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(restored.summary(provider: "claude", window: window(25), at: start.addingTimeInterval(60)).consumedPoints, 5)
        restored.clear(provider: "claude")
        XCTAssertTrue(restored.summary(provider: "claude", window: window(25), at: start.addingTimeInterval(60)).samples.isEmpty)
    }
    func testForecastUsesWholeCycleNotObservationStart() {
        let sampled = start.addingTimeInterval(3 * 3600)
        let result = QuotaForecast.calculate(window: window(30), sampledAt: sampled, now: sampled)!
        XCTAssertEqual(result.pointsPerHour, 10, accuracy: 0.0001)
        XCTAssertEqual(result.exhaustionDate!, start.addingTimeInterval(10 * 3600))
        XCTAssertEqual(result.projectedRemainingAtReset, 50, accuracy: 0.0001)
        XCTAssertEqual(result.runwayRatio, 3.5, accuracy: 0.0001)
        let short = QuotaForecast.calculate(window: window(80), sampledAt: sampled, now: sampled)!
        XCTAssertLessThan(short.runwayRatio, 1)
        XCTAssertEqual(short.projectedRemainingAtReset, 0)
    }
    func testUnknownStaleAndZeroConsumptionForecasts() {
        let sampled = start.addingTimeInterval(3600)
        XCTAssertNil(QuotaForecast.calculate(window: QuotaWindow(id: "x", title: "x", usedPercent: 20), sampledAt: sampled, now: sampled))
        XCTAssertNil(QuotaForecast.calculate(window: window(20), sampledAt: sampled, now: sampled.addingTimeInterval(151)))
        XCTAssertNil(QuotaForecast.calculate(window: window(20), sampledAt: sampled, now: sampled, stale: true))
        XCTAssertNil(QuotaForecast.calculate(window: window(20), sampledAt: start, now: start))
        XCTAssertNil(QuotaForecast.calculate(window: window(20), sampledAt: sampled, now: start.addingTimeInterval(18000)))
        let zero = QuotaForecast.calculate(window: window(0), sampledAt: sampled, now: sampled)!
        XCTAssertNil(zero.exhaustionDate)
        XCTAssertEqual(zero.runwayRatio, .infinity)
        XCTAssertEqual(zero.projectedRemainingAtReset, 100)
    }
    func testLegacyCacheDecodesWithoutCycleStart() throws {
        let old = Data(#"{"id":"x","title":"x","usedPercent":15}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(QuotaWindow.self, from: old).cycleStartedAt)
    }
    func testFullDayUsesOnlyLast24HoursAndInterpolatesBoundary() {
        var history = QuotaHistory()
        let metric = QuotaWindow(id: "weekly", title: "weekly", usedPercent: 0,
            resetsAt: start.addingTimeInterval(7 * 86400), cycleStartedAt: start)
        for minute in 0...1441 {
            var value = metric; value.usedPercent = Double(minute) * 0.01
            history.record(QuotaSnapshot(windows: [value], updatedAt: start.addingTimeInterval(Double(minute) * 60)), provider: "codex")
        }
        let now = start.addingTimeInterval(1441 * 60)
        let result = history.summary(provider: "codex", window: metric, at: now)
        XCTAssertEqual(result.consumedPoints!, 14.4, accuracy: 0.0001)
        XCTAssertFalse(result.isPartial)
        let halfway = history.summary(provider: "codex", window: metric, at: now.addingTimeInterval(30))
        XCTAssertEqual(halfway.consumedPoints!, 14.395, accuracy: 0.0001)
        XCTAssertFalse(halfway.hasGaps)
    }
    func testOfflineSameCycleRetainsKnownDeltaButMarksGap() {
        var history = QuotaHistory()
        history.record(QuotaSnapshot(windows: [window(10)], updatedAt: start), provider: "codex")
        history.record(QuotaSnapshot(windows: [window(30)], updatedAt: start.addingTimeInterval(3600)), provider: "codex")
        let result = history.summary(provider: "codex", window: window(30), at: start.addingTimeInterval(3600))
        XCTAssertEqual(result.consumedPoints, 20)
        XCTAssertTrue(result.hasGaps)
    }
    func testUrgencyHasContinuousThresholdsAndClampsExtremes() {
        XCTAssertEqual(QuotaUrgency.color(runwayRatio: 0), QuotaUrgency.color(runwayRatio: 0.35))
        XCTAssertEqual(QuotaUrgency.color(runwayRatio: .infinity), QuotaUrgency.color(runwayRatio: 1.25))
        for threshold in [0.35, 0.75, 1.0, 1.25] {
            let a = QuotaUrgency.color(runwayRatio: threshold - 0.000001)
            let b = QuotaUrgency.color(runwayRatio: threshold + 0.000001)
            XCTAssertEqual(a.red, b.red, accuracy: 0.00001)
            XCTAssertEqual(a.green, b.green, accuracy: 0.00001)
            XCTAssertEqual(a.blue, b.blue, accuracy: 0.00001)
        }
    }

    func testOfflineHistoryAgesOutOfThe24HourDisplay() {
        var history = QuotaHistory()
        history.record(QuotaSnapshot(windows: [window(20)], updatedAt: start), provider: "codex")
        history.record(QuotaSnapshot(windows: [window(25)], updatedAt: start.addingTimeInterval(60)), provider: "codex")
        let result = history.summary(provider: "codex", window: window(25), at: start.addingTimeInterval(25 * 3600))
        XCTAssertTrue(result.samples.isEmpty)
        XCTAssertNil(result.consumedPoints)
        XCTAssertTrue(result.isPartial)
    }


    func testCycleHistorySurvivesBeyond48HoursAndRoundTrips() throws {
        var history = QuotaHistory()
        let cycle = QuotaWindow(id: "month", title: "month", usedPercent: 10,
            resetsAt: start.addingTimeInterval(30 * 86400), cycleStartedAt: start)
        for hour in 0...240 {
            var value = cycle; value.usedPercent = Double(hour) / 10
            history.record(QuotaSnapshot(windows: [value], updatedAt: start.addingTimeInterval(Double(hour) * 3600)), provider: "cursor")
        }
        let restored = try JSONDecoder().decode(QuotaHistory.self, from: JSONEncoder().encode(history))
        let result = restored.summary(provider: "cursor", window: cycle, at: start.addingTimeInterval(240 * 3600))
        XCTAssertEqual(result.trendSamples.first?.date, start)
        XCTAssertEqual(result.samples.count, 25)
        XCTAssertEqual(result.consumedPoints!, 2.4, accuracy: 0.001)
    }
    func testRecentBarNeverIncludesPreviousCycleConsumption() {
        var history = QuotaHistory()
        for (seconds, value) in [(17880.0, window(60)), (17940.0, window(80)), (18060.0, window(5, cycle: 1))] {
            history.record(QuotaSnapshot(windows: [value], updatedAt: start.addingTimeInterval(seconds)), provider: "codex")
        }
        let latest = window(5, cycle: 1)
        let time = start.addingTimeInterval(18060)
        let result = history.summary(provider: "codex", window: latest, at: time)
        XCTAssertEqual(result.consumedPoints, 25)
        XCTAssertEqual(result.currentCycleRecentPoints, 5)
        XCTAssertEqual(result.trendSamples.count, 3)
        let forecast = QuotaForecast.calculate(window: latest, sampledAt: time, now: time, history: result)!
        XCTAssertTrue(forecast.usesRecentHistory)
        XCTAssertEqual(forecast.pointsPerHour, 500, accuracy: 0.001)
        XCTAssertNil(QuotaForecast.calculate(window: latest, sampledAt: time, now: time.addingTimeInterval(151), history: result))
    }
    func testFallbackRequiresObservedDurationAndReturnsToCycleMean() {
        var history = QuotaHistory()
        history.record(QuotaSnapshot(windows: [window(10)], updatedAt: start), provider: "codex")
        history.record(QuotaSnapshot(windows: [window(20)], updatedAt: start.addingTimeInterval(60)), provider: "codex")
        let summary = history.summary(provider: "codex", window: window(20), at: start.addingTimeInterval(60))
        var unknownStart = window(20); unknownStart.cycleStartedAt = nil
        let time = start.addingTimeInterval(60)
        XCTAssertNil(QuotaForecast.calculate(window: unknownStart, sampledAt: time, now: time))
        XCTAssertTrue(QuotaForecast.calculate(window: unknownStart, sampledAt: time, now: time, history: summary)!.usesRecentHistory)
        let later = start.addingTimeInterval(600)
        let result = QuotaForecast.calculate(window: window(20), sampledAt: later, now: later, history: summary)!
        XCTAssertFalse(result.usesRecentHistory)
        XCTAssertEqual(result.pointsPerHour, 120, accuracy: 0.001)
    }

    func testFreshCompletionMustAdvancePresentationClockBeforePublishing() {
        let lastTick = start.addingTimeInterval(3600)
        let completed = lastTick.addingTimeInterval(0.35)
        XCTAssertNil(QuotaForecast.calculate(window: window(30), sampledAt: completed, now: lastTick))
        let displayed = QuotaForecast.calculate(window: window(30), sampledAt: completed, now: completed)
        XCTAssertNotNil(displayed)
        XCTAssertEqual(displayed?.runwayRatio ?? 0,
                       QuotaForecast.calculate(window: window(30), sampledAt: completed, now: lastTick.addingTimeInterval(1))?.runwayRatio ?? -1)
        XCTAssertNil(QuotaForecast.calculate(window: window(30), sampledAt: completed, now: completed, stale: true))
    }

    func testRollingUnusedDeadlinesDoNotCreateRepeatedResetMarkers() {
        let old = QuotaSample(date: start.addingTimeInterval(-60), window: window(40, cycle: -1))
        var points = [old]
        for minute in 0..<120 {
            let date = start.addingTimeInterval(Double(minute) * 60)
            let value = QuotaWindow(id: "five", title: "5h", usedPercent: 0,
                resetsAt: date.addingTimeInterval(18000), cycleStartedAt: date)
            points.append(QuotaSample(date: date, window: value))
        }
        XCTAssertEqual(QuotaHistory.resetMarkers(in: points), [start])
        XCTAssertTrue(QuotaHistory.resetMarkers(in: Array(points.dropFirst())).isEmpty)
    }
    func testResetMarkersIgnoreDeadlineCorrectionsAndStillShowLaterRealReset() {
        let a = QuotaSample(date: start.addingTimeInterval(60), window: window(30))
        var corrected = window(30); corrected.resetsAt = corrected.resetsAt?.addingTimeInterval(60)
        corrected.cycleStartedAt = start.addingTimeInterval(60)
        let b = QuotaSample(date: start.addingTimeInterval(120), window: corrected)
        let c = QuotaSample(date: start.addingTimeInterval(18120), window: window(2, cycle: 1))
        XCTAssertTrue(QuotaHistory.resetMarkers(in: [a, b]).isEmpty)
        XCTAssertEqual(QuotaHistory.resetMarkers(in: [a, b, c]), [start.addingTimeInterval(18000)])
    }
    func testLongCycleUsesRecentHistoryUntilOneDay() {
        var history = QuotaHistory()
        let before = start.addingTimeInterval(-60)
        let after = start.addingTimeInterval(60)
        history.record(QuotaSnapshot(windows: [window(60, cycle: -1)], updatedAt: before), provider: "codex")
        let weekly = QuotaWindow(id: "five", title: "5h", usedPercent: 5,
            resetsAt: start.addingTimeInterval(7 * 86400), cycleStartedAt: start)
        history.record(QuotaSnapshot(windows: [weekly], updatedAt: after), provider: "codex")
        let summary = history.summary(provider: "codex", window: weekly, at: after)
        for seconds in [3600.0, 86399.0] {
            let time = start.addingTimeInterval(seconds)
            let result = QuotaForecast.calculate(window: weekly, sampledAt: time, now: time, history: summary)!
            XCTAssertTrue(result.usesRecentHistory)
            XCTAssertEqual(result.pointsPerHour, summary.consumedPoints! / summary.observedSeconds * 3600, accuracy: 0.001)
        }
        let time = start.addingTimeInterval(86400)
        let result = QuotaForecast.calculate(window: weekly, sampledAt: time, now: time, history: summary)!
        XCTAssertFalse(result.usesRecentHistory)
        XCTAssertEqual(result.pointsPerHour, 5.0 / 24, accuracy: 0.001)
        let shortTime = start.addingTimeInterval(3600)
        XCTAssertFalse(QuotaForecast.calculate(window: window(5), sampledAt: shortTime, now: shortTime, history: summary)!.usesRecentHistory)
    }

}
