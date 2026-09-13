import Foundation

public struct QuotaSample: Codable, Equatable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let window: QuotaWindow
}

public struct UsageHistorySummary {
    public let samples: [QuotaSample]
    public let trendSamples: [QuotaSample]
    public let currentCycleRecentPoints: Double?
    public let consumedPoints: Double?
    public let observedSeconds: TimeInterval
    public let isPartial: Bool
    public let hasGaps: Bool
}

public struct QuotaHistory: Codable {
    public var version = 1
    private var series: [String: [QuotaSample]] = [:]
    public init() {}
    private func key(_ provider: String, _ window: QuotaWindow) -> String {
        // Length prefixes keep arbitrary metric titles from colliding with another series.
        "\(provider.count):\(provider)\(window.id.count):\(window.id)\(window.title)"
    }
    public mutating func clear(provider: String) {
        series = series.filter { !$0.key.hasPrefix("\(provider.count):\(provider)") }
    }
    public mutating func record(_ snapshot: QuotaSnapshot, provider: String) {
        for window in snapshot.windows where window.usedPercent.isFinite && window.usedPercent >= 0 {
            let key = key(provider, window)
            var values = series[key] ?? []
            guard values.last.map({ $0.date < snapshot.updatedAt }) ?? true else { continue }
            values.append(QuotaSample(date: snapshot.updatedAt, window: window))
            series[key] = values
        }
        // Preserve the current cycle, thinning old samples to 15-minute buckets.
        let cutoff = snapshot.updatedAt.addingTimeInterval(-48 * 3600)
        series = series.compactMapValues { values in
            guard let latest = values.last else { return nil }
            let start = min(cutoff, latest.window.cycleStartedAt ?? cutoff)
            var kept: [QuotaSample] = []
            for value in values where value.date >= start {
                if value.date >= cutoff || kept.last.map({ value.date.timeIntervalSince($0.date) >= 900 || !Self.sameCycle($0.window, value.window) }) ?? true {
                    kept.append(value)
                }
            }
            return Array(kept.suffix(40000))
        }
    }

    public func summary(provider: String, window: QuotaWindow, at now: Date) -> UsageHistorySummary {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        let all = (series[key(provider, window)] ?? []).filter { $0.date <= now }
        let visible = all.filter { $0.date >= cutoff }
        let anchor = all.last { $0.date < cutoff }
        let values = (anchor.map { [$0] } ?? []) + visible
        var consumed = 0.0
        var intervals = 0
        var gaps = false
        for (previous, current) in zip(values, values.dropFirst()) {
            let same = Self.sameCycle(previous.window, current.window)
            if previous.date < cutoff {
                let interval = current.date.timeIntervalSince(previous.date)
                if interval > 0, interval <= 150, same, current.window.usedPercent >= previous.window.usedPercent {
                    // Estimate only the sub-minute boundary portion; never interpolate a reset or offline gap.
                    consumed += (current.window.usedPercent - previous.window.usedPercent) * current.date.timeIntervalSince(cutoff) / interval
                    intervals += 1
                } else { gaps = true }
                continue
            }
            if same, current.window.usedPercent >= previous.window.usedPercent {
                consumed += current.window.usedPercent - previous.window.usedPercent
                intervals += 1
            } else if let start = current.window.cycleStartedAt,
                      let oldReset = previous.window.resetsAt,
                      oldReset <= current.date, start >= previous.date, start <= current.date,
                      start >= cutoff {
                // The new cycle's cumulative usage is known; the old cycle's unobserved tail is not.
                consumed += current.window.usedPercent
                intervals += 1
                if previous.window.remaining > 0 { gaps = true }
            } else {
                gaps = true
            }
            if current.date.timeIntervalSince(previous.date) > 150 { gaps = true }
        }
        let first = visible.first?.date ?? now
        let last = visible.last?.date ?? now
        let duration = max(0, last.timeIntervalSince(first))
        let coversStart = first.timeIntervalSince(cutoff) <= 90
        let coversEnd = now.timeIntervalSince(last) <= 150
        let cycleValues = values.filter { Self.sameCycle($0.window, window) }
        var recent: Double? = nil
        if let start = window.cycleStartedAt, start >= cutoff, start <= now {
            recent = min(100, window.usedPercent)
        } else if cycleValues.count > 1 {
            recent = 0
            for (a, b) in zip(cycleValues, cycleValues.dropFirst()) where b.window.usedPercent >= a.window.usedPercent {
                let fraction = a.date < cutoff ? (b.date.timeIntervalSince(cutoff) / b.date.timeIntervalSince(a.date)) : 1
                if a.date >= cutoff || b.date.timeIntervalSince(a.date) <= 150 {
                    recent! += (b.window.usedPercent - a.window.usedPercent) * max(0, min(1, fraction))
                }
            }
        }
        let trendStart = min(cutoff, window.cycleStartedAt ?? cutoff)
        return UsageHistorySummary(samples: visible, trendSamples: all.filter { $0.date >= trendStart },
            currentCycleRecentPoints: recent.map { min(max(0, $0), min(100, window.usedPercent)) }, consumedPoints: intervals > 0 ? consumed : nil,
            observedSeconds: duration, isPartial: !coversStart || !coversEnd || gaps, hasGaps: gaps)
    }
    /// An unused quota can have a rolling reset deadline. Metadata movement alone is not a reset event.
    public static func resetMarkers(in samples: [QuotaSample]) -> [Date] {
        var markers: [Date] = []
        for (previous, current) in zip(samples, samples.dropFirst()) {
            guard previous.window.id == current.window.id, previous.window.title == current.window.title,
                  !sameCycle(previous.window, current.window), previous.window.usedPercent > 0,
                  let start = current.window.cycleStartedAt, let oldReset = previous.window.resetsAt,
                  start >= previous.date, start <= current.date,
                  oldReset <= current.date || current.window.usedPercent < previous.window.usedPercent else { continue }
            if markers.last.map({ abs(start.timeIntervalSince($0)) >= 1 }) ?? true { markers.append(start) }
        }
        return markers
    }

    public static func sameCycle(_ a: QuotaWindow, _ b: QuotaWindow) -> Bool {
        guard a.id == b.id, a.title == b.title else { return false }
        if let x = a.resetsAt, let y = b.resetsAt { return abs(x.timeIntervalSince(y)) < 1 }
        // Without reset metadata, a decrease or restoration is ambiguous, so never bridge it.
        return a.resetsAt == nil && b.resetsAt == nil && b.usedPercent >= a.usedPercent
    }
}

public struct QuotaForecast: Equatable {
    public let usesRecentHistory: Bool
    public let pointsPerHour: Double
    public let exhaustionDate: Date?
    public let projectedRemainingAtReset: Double
    /// Estimated time to exhaustion / time left before reset. 1 means just enough.
    public let runwayRatio: Double

    public static func calculate(window: QuotaWindow, sampledAt: Date, now: Date, stale: Bool = false, history: UsageHistorySummary? = nil) -> QuotaForecast? {
        guard !stale, sampledAt <= now, now.timeIntervalSince(sampledAt) <= 150,
              window.usedPercent.isFinite, window.usedPercent >= 0,
              let reset = window.resetsAt, sampledAt < reset, now < reset else { return nil }
        if let start = window.cycleStartedAt, start > sampledAt { return nil }
        let elapsed = window.cycleStartedAt.map { sampledAt.timeIntervalSince($0) }
        // Long cycles need a full day before their mean reflects both active and sleeping hours.
        let cycleDuration = window.cycleStartedAt.map { reset.timeIntervalSince($0) }
        let warmup: TimeInterval = (cycleDuration ?? 0) > 5 * 3600 ? 24 * 3600 : 300
        let useRecent = elapsed == nil || elapsed! < warmup
        let rate: Double
        if useRecent, let history, let consumed = history.consumedPoints, history.observedSeconds >= 60 {
            rate = consumed / history.observedSeconds
        } else if let elapsed, elapsed > 0 {
            rate = window.usedPercent / elapsed
        } else { return nil }
        let recentBasis = useRecent && history?.consumedPoints != nil && (history?.observedSeconds ?? 0) >= 60
        guard rate.isFinite else { return nil }
        if rate == 0 {
            return QuotaForecast(usesRecentHistory: recentBasis, pointsPerHour: 0, exhaustionDate: nil, projectedRemainingAtReset: 100, runwayRatio: .infinity)
        }
        let seconds = window.remaining / rate
        let remainingTime = reset.timeIntervalSince(sampledAt)
        return QuotaForecast(usesRecentHistory: recentBasis, pointsPerHour: rate * 3600, exhaustionDate: sampledAt.addingTimeInterval(seconds),
            projectedRemainingAtReset: max(0, window.remaining - rate * remainingTime), runwayRatio: seconds / remainingTime)
    }
}

public enum QuotaUrgency {
    public struct RGB: Equatable { public let red: Double; public let green: Double; public let blue: Double }
    public static func color(runwayRatio: Double) -> RGB {
        let stops: [(Double, RGB)] = [
            (0.35, RGB(red: 0.90, green: 0.30, blue: 0.37)),
            (0.75, RGB(red: 0.94, green: 0.63, blue: 0.57)),
            (1.0, RGB(red: 0.89, green: 0.78, blue: 0.45)),
            (1.25, RGB(red: 0.46, green: 0.83, blue: 0.68))
        ]
        if runwayRatio <= stops[0].0 { return stops[0].1 }
        for (a, b) in zip(stops, stops.dropFirst()) where runwayRatio < b.0 {
            let t = max(0, (runwayRatio - a.0) / (b.0 - a.0))
            return RGB(red: a.1.red + (b.1.red - a.1.red) * t,
                green: a.1.green + (b.1.green - a.1.green) * t,
                blue: a.1.blue + (b.1.blue - a.1.blue) * t)
        }
        return stops.last!.1
    }
}
