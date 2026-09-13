import Foundation

public extension QuotaParser {
    static func claude(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        struct Window: Decodable { let utilization: Double?; let resets_at: String? }
        struct Response: Decodable {
            let five_hour: Window?
            let seven_day: Window?
            let seven_day_sonnet: Window?
            let seven_day_opus: Window?
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw QuotaError.invalidData("Claude 用量格式发生变化，请稍后重试") }
        let fields: [(String, String, Window?)] = [
            ("five_hour", "5 小时额度", response.five_hour),
            ("seven_day", "每周额度", response.seven_day),
            ("seven_day_sonnet", "Sonnet 每周", response.seven_day_sonnet),
            ("seven_day_opus", "Opus 每周", response.seven_day_opus)
        ]
        var windows: [QuotaWindow] = []
        for (id, title, value) in fields {
            guard let value, let used = value.utilization else { continue }
            guard used.isFinite, used >= 0 else { throw QuotaError.invalidData("Claude 返回无效用量") }
            var reset: Date?
            if let text = value.resets_at {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reset = formatter.date(from: text)
                if reset == nil { formatter.formatOptions = [.withInternetDateTime]; reset = formatter.date(from: text) }
                guard reset != nil else { throw QuotaError.invalidData("Claude 重置时间无法识别") }
            }
            windows.append(QuotaWindow(id: id, title: title, usedPercent: used, resetsAt: reset,
                cycleStartedAt: reset?.addingTimeInterval(id == "five_hour" ? -5 * 3600 : -7 * 86400)))
        }
        guard !windows.isEmpty else { throw QuotaError.invalidData("Claude 尚未提供订阅额度，请检查账号与订阅") }
        return QuotaSnapshot(windows: windows, updatedAt: now)
    }
}
