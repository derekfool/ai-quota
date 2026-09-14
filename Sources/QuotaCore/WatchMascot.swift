import Foundation

public enum WatchMascot: Int, CaseIterable {
    case sad, blank, lying

    public var assetName: String { ["sad", "blank", "lying"][rawValue] }
    public var exitDuration: Double { self == .lying ? 0.28 : 0.22 }
    public var axis: (x: Double, y: Double) {
        let angle = -0.32
        let dx = -0.005, dy = 0.36
        let length = hypot(dx, dy)
        return ((dx * cos(angle) - dy * sin(angle)) / length,
                (dx * sin(angle) + dy * cos(angle)) / length)
    }

    public func visibility(elapsed: Double, exiting: Bool) -> Double {
        if exiting {
            let t = min(1, max(0, (elapsed - (self == .lying ? 0.06 : 0)) / 0.22))
            return 1 - t * t * (3 - 2 * t)
        }
        let t = min(1, max(0, elapsed / 0.30))
        return 1 - pow(1 - t, 3)
    }

    /// Two brief ear flicks, separated by a long quiet interval after settling in.
    public func earTwitch(at elapsed: Double) -> Double {
        guard self == .lying, elapsed >= 2.4 else { return 0 }
        let t = (elapsed - 2.4).truncatingRemainder(dividingBy: 8.7)
        func pulse(_ start: Double, _ duration: Double) -> Double {
            guard t >= start, t <= start + duration else { return 0 }
            return pow(sin(.pi * (t - start) / duration), 2)
        }
        return pulse(0, 0.28) + 0.6 * pulse(0.38, 0.24)
    }

    public func blink(at elapsed: Double) -> Double {
        let t = elapsed < 1.2 ? elapsed : 1.2 + (elapsed - 1.2).truncatingRemainder(dividingBy: 6.3)
        return [0.55, 0.88, 3.9, 6.3].map { max(0, 1 - abs(t - $0) / 0.12) }.max() ?? 0
    }
}
