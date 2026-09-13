import Foundation
import CoreFoundation

public extension QuotaParser {
    /// Payload of Gemini web's GetUsageInfo (jSf9Qc), not Gemini CLI or API quota.
    static func gemini(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any], root.count >= 2,
              let pools = root[1] as? [[Any]] else { throw QuotaError.invalidData("Gemini 用量格式已变化") }
        func number(_ value: Any) -> Double? {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        var windows: [QuotaWindow] = []
        for pool in pools {
            guard pool.count >= 3, let kind = number(pool[2]), kind == 1 || kind == 2 else { continue }
            let id = kind == 1 ? "five_hour" : "seven_day"
            guard !windows.contains(where: { $0.id == id }), let fraction = number(pool[1]), fraction >= 0 else {
                throw QuotaError.invalidData("Gemini 返回无效或重复额度")
            }
            var reset: Date?
            if pool.count > 3, !(pool[3] is NSNull) {
                guard let wrapper = pool[3] as? [Any], let timestamp = wrapper.first as? [Any],
                      let secondsValue = timestamp.first, let seconds = number(secondsValue), seconds > 0 else {
                    throw QuotaError.invalidData("Gemini 重置时间无法识别")
                }
                let nanos = timestamp.count > 1 ? number(timestamp[1]) : 0
                guard let nanos, nanos >= 0, nanos < 1_000_000_000 else { throw QuotaError.invalidData("Gemini 重置时间无法识别") }
                reset = Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000)
            }
            // Google frontend Ypm multiplies field 2 by 100; field 3 selects current=1 / weekly=2.
            windows.append(QuotaWindow(id: id, title: kind == 1 ? "5 小时额度" : "每周额度",
                usedPercent: fraction * 100, resetsAt: reset,
                cycleStartedAt: reset?.addingTimeInterval(kind == 1 ? -5 * 3600 : -7 * 86400)))
        }
        guard !windows.isEmpty else { throw QuotaError.invalidData("Gemini 尚未提供订阅额度，请打开官方用量页检查") }
        windows.sort { $0.id < $1.id }
        return QuotaSnapshot(windows: windows, updatedAt: now)
    }
}
