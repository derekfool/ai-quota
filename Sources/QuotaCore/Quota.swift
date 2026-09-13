import Foundation

public struct QuotaWindow: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var cycleStartedAt: Date?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public init(id: String, title: String, usedPercent: Double, resetsAt: Date? = nil, cycleStartedAt: Date? = nil) {
        self.id = id; self.title = title; self.usedPercent = usedPercent; self.resetsAt = resetsAt; self.cycleStartedAt = cycleStartedAt
    }
}

public struct QuotaSnapshot: Codable, Equatable {
    public var windows: [QuotaWindow]
    public var updatedAt: Date
    public var resetNote: String?
    public init(windows: [QuotaWindow], updatedAt: Date = Date(), resetNote: String? = nil) {
        self.windows = windows; self.updatedAt = updatedAt; self.resetNote = resetNote
    }
    public func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 150 || windows.contains { $0.resetsAt.map { $0 <= now } ?? false } }
    public var minimumRemaining: Double? { windows.map(\.remaining).min() }
}

public enum QuotaError: LocalizedError {
    case invalidData(String)
    public var errorDescription: String? { if case .invalidData(let text) = self { return text }; return nil }
}

public enum QuotaParser {
    static func isoDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    public static func codex(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        struct Window: Decodable { let usedPercent: Double; let windowDurationMins: Int?; let resetsAt: Double? }
        struct Limits: Decodable { let primary: Window?; let secondary: Window? }
        struct Response: Decodable { let rateLimits: Limits?; let rateLimitsByLimitId: [String: Limits]? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        // Prefer the named Codex pool; the legacy bucket can describe another model pool.
        let limits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        let windows = [("primary", limits?.primary), ("secondary", limits?.secondary)].compactMap { id, value -> QuotaWindow? in
            guard let value, value.usedPercent.isFinite, value.usedPercent >= 0 else { return nil }
            let minutes = value.windowDurationMins
            let title: String
            if minutes == 10080 { title = "每周额度" }
            else if let minutes, minutes > 0, minutes % 60 == 0 { title = "\(minutes / 60) 小时额度" }
            else if let minutes, minutes > 0 { title = "\(minutes) 分钟额度" }
            else { title = id == "primary" ? "主要额度" : "次要额度" }
            let reset = value.resetsAt.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
            let start = minutes.flatMap { $0 > 0 ? reset?.addingTimeInterval(-Double($0) * 60) : nil }
            return QuotaWindow(id: id, title: title, usedPercent: value.usedPercent, resetsAt: reset, cycleStartedAt: start)
        }
        guard !windows.isEmpty else { throw QuotaError.invalidData("Codex 未返回可用额度，请检查登录状态") }
        return QuotaSnapshot(windows: windows, updatedAt: now)
    }

    public static func cursorSummary(_ data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        struct Plan: Decodable { let autoPercentUsed: Double?; let apiPercentUsed: Double? }
        struct Individual: Decodable { let plan: Plan? }
        struct Summary: Decodable { let individualUsage: Individual?; let billingCycleEnd: String?; let billingCycleStart: String? }
        let summary: Summary
        do { summary = try JSONDecoder().decode(Summary.self, from: data) }
        catch { throw QuotaError.invalidData("Cursor 用量格式已变化，请打开官方页面检查") }
        guard let cursorUsed = summary.individualUsage?.plan?.autoPercentUsed,
              let otherUsed = summary.individualUsage?.plan?.apiPercentUsed,
              cursorUsed.isFinite, otherUsed.isFinite, cursorUsed >= 0, otherUsed >= 0 else {
            throw QuotaError.invalidData("Cursor 未返回两类完整额度，请稍后刷新")
        }
        var reset: Date?
        if let value = summary.billingCycleEnd {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            reset = formatter.date(from: value)
            if reset == nil { formatter.formatOptions = [.withInternetDateTime]; reset = formatter.date(from: value) }
        }
        let start = summary.billingCycleStart.flatMap(Self.isoDate)
        return QuotaSnapshot(windows: [
            QuotaWindow(id: "Cursor Models", title: "Cursor Models", usedPercent: cursorUsed, resetsAt: reset, cycleStartedAt: start),
            QuotaWindow(id: "Other Models", title: "Other Models", usedPercent: otherUsed, resetsAt: reset, cycleStartedAt: start)
        ], updatedAt: now)
    }

    public static func cursor(_ text: String, now: Date = Date()) throws -> QuotaSnapshot {
        let flat = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard flat.contains("Cursor Models"), flat.contains("Other Models") else { throw QuotaError.invalidData("Cursor 页面尚未提供完整额度，请稍后刷新") }
        func capture(_ pattern: String, in value: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let range = Range(result.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
        var windows: [QuotaWindow] = []
        // Bound each section so a missing pool percentage cannot borrow an on-demand or other-pool value.
        for (name, boundary) in [("Cursor Models", "Other Models"), ("Other Models", "Grok Bot|Weekly usage|On-Demand")] {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = escapedName + "(.*?)(?=" + boundary + "|" + escapedName + "|$)"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let sections = regex.matches(in: flat, range: NSRange(flat.startIndex..., in: flat)).compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: flat) else { return nil }
                return String(flat[range])
            }
            let values = sections.compactMap { capture("([0-9]+(?:\\.[0-9]+)?)\\s*%\\s*used", in: $0) }.compactMap(Double.init)
            guard values.count == 1, let used = values.first, used.isFinite, used >= 0 else {
                throw QuotaError.invalidData("无法识别 Cursor 额度，保留上次数据")
            }
            windows.append(QuotaWindow(id: name, title: name, usedPercent: used))
        }
        let note = capture("Usage limits reset on\\s+(.+?)(?=Adjust Plan|UPGRADE AVAILABLE|Ultra|Cursor Models|$)", in: flat)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Preserve the source's billing-date text; it omits an exact reset time/timezone.
        return QuotaSnapshot(windows: windows, updatedAt: now, resetNote: note)
    }
}
