import Foundation

/// One provider's polling cadence. Focus mode is temporary and never persisted.
public struct RefreshSchedule: Equatable {
    public private(set) var watchingUntil: Date?
    public private(set) var nextRefreshAt: Date = .distantPast
    public init() {}

    public func secondsRemaining(at now: Date) -> Int {
        guard let watchingUntil else { return 0 }
        return max(0, Int(ceil(watchingUntil.timeIntervalSince(now))))
    }
    public mutating func startWatching(at now: Date, durationMinutes: Int = 10) {
        watchingUntil = now.addingTimeInterval(Double(max(1, durationMinutes)) * 60)
        nextRefreshAt = now
    }
    public mutating func stopWatching(at now: Date) {
        watchingUntil = nil
        nextRefreshAt = now.addingTimeInterval(60)
    }
    public mutating func expireIfNeeded(at now: Date) {
        if let watchingUntil, now >= watchingUntil { stopWatching(at: now) }
    }
    public mutating func recordRefresh(at now: Date) {
        expireIfNeeded(at: now)
        nextRefreshAt = now.addingTimeInterval(watchingUntil == nil ? 60 : 10)
    }
    public mutating func takeDueRefresh(at now: Date, requestInFlight: Bool) -> Bool {
        expireIfNeeded(at: now)
        guard now >= nextRefreshAt else { return false }
        // Skip a busy slot instead of queueing requests or issuing a catch-up burst after sleep.
        recordRefresh(at: now)
        return !requestInFlight
    }
}
