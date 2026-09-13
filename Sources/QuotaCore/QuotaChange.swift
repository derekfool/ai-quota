import Foundation

public enum ChangeIntensity: Int, Comparable {
    case small, large, major
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var duration: TimeInterval {
        switch self { case .small: return 1.8; case .large: return 2.8; case .major: return 4 }
    }
}

public struct QuotaChange: Identifiable, Equatable {
    public let id: UUID
    public let deltas: [String: Int]
    public let startedAt: Date
    public let isPreview: Bool
    public var dominantDelta: Int { deltas.values.sorted { abs($0) == abs($1) ? $0 < $1 : abs($0) > abs($1) }.first ?? 0 }
    public var intensity: ChangeIntensity { abs(dominantDelta) >= 20 ? .major : abs(dominantDelta) >= 3 ? .large : .small }
    public var expiresAt: Date { startedAt.addingTimeInterval(30) }
    public init(deltas: [String: Int], startedAt: Date = Date(), isPreview: Bool = false) {
        self.id = UUID(); self.deltas = deltas; self.startedAt = startedAt; self.isPreview = isPreview
    }
}

public struct QuotaChangeTracker {
    private var previous: QuotaSnapshot?
    public init() {}
    public mutating func accept(_ snapshot: QuotaSnapshot) -> QuotaChange? {
        defer { previous = snapshot }
        guard let previous else { return nil }
        let age = snapshot.updatedAt.timeIntervalSince(previous.updatedAt)
        // Reconnects and cache restoration establish a new baseline, rather than announcing a stale jump.
        guard age >= 0, age <= 150 else { return nil }
        var deltas: [String: Int] = [:]
        for window in snapshot.windows {
            // A primary slot may change from a five-hour to a weekly bucket after a plan change.
            guard let old = previous.windows.first(where: { $0.id == window.id && $0.title == window.title }) else { continue }
            let delta = Int(window.remaining.rounded()) - Int(old.remaining.rounded())
            if delta != 0 { deltas[window.id] = delta }
        }
        guard !deltas.isEmpty else { return nil }
        return QuotaChange(deltas: deltas, startedAt: snapshot.updatedAt)
    }
}
