import SwiftUI
import QuotaCore

struct MetricView: View {
    let window: QuotaWindow
    let history: UsageHistorySummary?
    let sampledAt: Date
    let now: Date
    let stale: Bool
    let change: QuotaChange?
    @State private var expanded = false
    @AppStorage("appLanguage") private var languageCode = AppLanguage.current.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var forecast: QuotaForecast? { QuotaForecast.calculate(window: window, sampledAt: sampledAt, now: now, stale: stale, history: history) }
    private var delta: Int? { change?.deltas[window.id] }
    private var changeTone: Color { (delta ?? 0) > 0 ? .mint : Color(red: 1, green: 0.60, blue: 0.58) }
    private var tone: Color {
        guard let forecast, !stale else { return .white }
        let rgb = QuotaUrgency.color(runwayRatio: forecast.runwayRatio)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    private let olderTone = Color(red: 0.31, green: 0.35, blue: 0.43)
    private let recentTone = Color(red: 0.51, green: 0.59, blue: 0.67)
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(localized(window.title)).font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 5) {
                            GeometryReader { geometry in
                                let used = 100 - window.remaining
                                let recent = min(used, history?.currentCycleRecentPoints ?? 0)
                                HStack(spacing: 0) {
                                    tone.frame(width: geometry.size.width * window.remaining / 100)
                                    recentTone.frame(width: geometry.size.width * recent / 100)
                                    olderTone.frame(width: geometry.size.width * (used - recent) / 100)
                                }.clipShape(Capsule())
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: window.remaining)
                            }.frame(height: 7)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }.frame(height: 14).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(L("\(expanded ? "收起" : "展开") \(localized(window.title))周期趋势", "\(expanded ? "Collapse" : "Expand") \(localized(window.title)) cycle trend"))
                        .help(L("深灰蓝：更早已用；雾蓝：本周期近24h已用；鲜艳段：剩余，红黄绿表示能否撑到重置。历史不足时分段仅表示已知部分。", "Dark gray-blue: earlier usage. Mist blue: this cycle’s last 24h usage. Color: remaining quota; green/yellow/red indicates runway until reset. Partial history shows known usage only."))
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(window.remaining.rounded()))%")
                        .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        .modifier(QuotaNumericTransition(value: window.remaining))
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: window.remaining)
                    Text(delta.map { L("\(change?.isPreview == true ? "预览 " : "")\($0 > 0 ? "↑" : "↓") \(abs($0))% · 刚刚", "\(change?.isPreview == true ? "Preview " : "")\($0 > 0 ? "↑" : "↓") \(abs($0))% · just now") } ?? historyText)
                        .font(.system(size: 9, weight: delta == nil ? .regular : .semibold))
                        .foregroundStyle(delta == nil ? Color.secondary : changeTone)
                        .frame(width: 112, height: 13, alignment: .trailing)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .help(L("\(historyText)。变化百分号表示额度百分点，例如66%到63%显示↓3%。", "\(historyText). Changes are percentage points: 66% to 63% is shown as ↓3%."))
                        .help(L("过去24小时累计消耗（百分点），可跨重置超过100点。带 * 表示历史不足或存在缺口；记录 \(Self.duration(history?.observedSeconds ?? 0))。", "Usage over the last 24h in percentage points; may exceed 100 across resets. * means partial history or gaps. Observed: \(Self.duration(history?.observedSeconds ?? 0))."))
                }.fixedSize()
            }
            HStack(alignment: .top, spacing: 6) {
                Text(forecastText).foregroundStyle(tone)
                Spacer(minLength: 2)
                if let reset = window.resetsAt {
                    Text(reset <= now ? L("等待重置同步", "Waiting for reset sync") : L("\(Self.duration(reset.timeIntervalSince(now)))后重置", "\(Self.duration(reset.timeIntervalSince(now))) until reset"))
                        .foregroundStyle(.secondary).fixedSize()
                }
            }.font(.system(size: 9)).fixedSize(horizontal: false, vertical: true)
            if expanded {
                CycleTrend(window: window, samples: history?.trendSamples ?? [], forecast: forecast, sampledAt: sampledAt, now: now, tone: tone)
                    .frame(height: 138)
                Text(detailText).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(delta == nil ? Color.clear : changeTone.opacity(0.25)))
        .overlay(alignment: .leading) {
            if delta != nil { Capsule().fill(changeTone).frame(width: 4).padding(.vertical, 4) }
        }
    }
    private var historyText: String {
        guard let history, let used = history.consumedPoints else { return L("24h 用量 · 积累中", "24h used · collecting") }
        return L("24h 用量 \(used.formatted(.number.precision(.fractionLength(1)))) 点\(history.isPartial ? "*" : "")", "24h used \(used.formatted(.number.precision(.fractionLength(1)))) pp\(history.isPartial ? "*" : "")")
    }
    private var forecastText: String {
        guard let forecast else { return stale ? L("预测暂停 · 等待同步", "Forecast paused · awaiting sync") : L("预测暂缺周期信息", "Cycle dates unavailable") }
        let basis = forecast.usesRecentHistory ? L(" · 24h估算", " · 24h estimate") : ""
        guard let date = forecast.exhaustionDate else { return L("暂无消耗 · 余量充足", "No usage · ample quota") + basis }
        if date <= now { return L("按均速预计已耗尽", "Estimated exhausted at current rate") + basis }
        return L("可用约 \(Self.duration(date.timeIntervalSince(now)))", "Runway ~\(Self.duration(date.timeIntervalSince(now)))") + (forecast.runwayRatio < 1 ? L(" · 提前耗尽", " · runs out early") : "") + basis
    }
    private var detailText: String {
        guard let forecast else { return L("实线为已记录用量；缺失区间留空。需有效周期信息和最新额度才能预测。", "Solid lines show recorded usage; gaps remain blank. Forecasts require valid cycle dates and fresh data.") }
        let basis = forecast.usesRecentHistory ? L("按近24h已记录 \(Self.duration(history?.observedSeconds ?? 0)) 均速估算", "Based on the observed \(Self.duration(history?.observedSeconds ?? 0)) within the last 24h") : L("按本周期累计用量 / 周期已过时间预测", "Based on cycle usage / elapsed cycle time")
        let result: String
        if let date = forecast.exhaustionDate, let reset = window.resetsAt, date < reset {
            result = L("预计提前 \(Self.duration(reset.timeIntervalSince(date)))耗尽", "Runs out \(Self.duration(reset.timeIntervalSince(date))) early")
        } else { result = L("周期结束预计剩余 \(Int(forecast.projectedRemainingAtReset.rounded()))%", "Remaining at reset: \(Int(forecast.projectedRemainingAtReset.rounded()))%") }
        return L("\(basis)，每小时约 \(forecast.pointsPerHour.formatted(.number.precision(.fractionLength(2)))) 点；\(result)。实线为历史，虚线为预测；重置与缺口不连线。", "\(basis), approximately \(forecast.pointsPerHour.formatted(.number.precision(.fractionLength(2)))) pp/hour; \(result). Solid: history. Dashed: forecast. Resets and gaps are not connected.")
    }
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds < 3650 * 86400 else { return L("超过10年", "Over 10 years") }
        let minutes = max(1, Int(max(0, seconds) / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

private struct CycleTrend: View {
    @AppStorage("appLanguage") private var languageCode = AppLanguage.current.rawValue
    let window: QuotaWindow
    let samples: [QuotaSample]
    let forecast: QuotaForecast?
    let sampledAt: Date
    let now: Date
    let tone: Color
    private var rangeStart: Date { min(window.cycleStartedAt ?? sampledAt.addingTimeInterval(-86400), samples.first?.date ?? sampledAt) }
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(L("已用 % · 周期与近24h历史", "Used % · cycle + last 24h"))
                Spacer()
                Text(L("实线 历史 · 虚线 预测", "Solid: history · dashed: forecast"))
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            Canvas { context, size in
                let start = rangeStart
                let end = max(window.resetsAt ?? now, now.addingTimeInterval(60))
                let span = max(1, end.timeIntervalSince(start))
                func point(_ date: Date, _ used: Double) -> CGPoint {
                    CGPoint(x: 24 + max(0, min(1, date.timeIntervalSince(start) / span)) * (size.width - 28),
                            y: 5 + (1 - max(0, min(100, used)) / 100) * (size.height - 12))
                }
                for value in [0.0, 50, 100] {
                    let y = point(start, value).y
                    var grid = Path(); grid.move(to: CGPoint(x: 24, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(.white.opacity(0.10)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    context.draw(Text("\(Int(value))").font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: 10, y: y))
                }
                var previous: QuotaSample?
                var path = Path()
                for sample in samples {
                    let p = point(sample.date, sample.window.usedPercent)
                    if let old = previous, QuotaHistory.sameCycle(old.window, sample.window),
                       sample.window.usedPercent >= old.window.usedPercent,
                       sample.date.timeIntervalSince(old.date) <= (sample.date < now.addingTimeInterval(-172800) ? 1050 : 150) {
                        path.addLine(to: p)
                    } else {
                        path.move(to: p)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(.gray))
                    }
                    previous = sample
                }
                for reset in QuotaHistory.resetMarkers(in: samples) where reset >= start && reset <= end {
                    var marker = Path(); marker.move(to: point(reset, 0)); marker.addLine(to: point(reset, 100))
                    context.stroke(marker, with: .color(.gray), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    context.draw(Text(L("重置", "Reset")).font(.system(size: 8)).foregroundColor(.secondary), at: point(reset, 85))
                }
                context.stroke(path, with: .color(Color(red: 0.57, green: 0.66, blue: 0.73)), lineWidth: 1.5)
                if let forecast {
                    let until = min(end, forecast.exhaustionDate ?? end)
                    let used = window.usedPercent + forecast.pointsPerHour * until.timeIntervalSince(sampledAt) / 3600
                    var prediction = Path(); prediction.move(to: point(sampledAt, window.usedPercent)); prediction.addLine(to: point(until, used))
                    context.stroke(prediction, with: .color(tone), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    let p = point(until, used)
                    if used >= 100 {
                        context.draw(Text(L("预计耗尽", "Exhaustion")).font(.system(size: 8)).foregroundColor(tone), at: CGPoint(x: min(size.width - 24, max(48, p.x)), y: p.y + 12))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(tone))
                }
                let current = point(sampledAt, window.usedPercent)
                var marker = Path(); marker.move(to: CGPoint(x: current.x, y: 5)); marker.addLine(to: CGPoint(x: current.x, y: size.height - 7))
                context.stroke(marker, with: .color(.gray.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                context.draw(Text(L("现在", "Now")).font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: min(size.width - 16, max(40, current.x)), y: size.height - 5))
                context.fill(Path(ellipseIn: CGRect(x: current.x - 2, y: current.y - 2, width: 4, height: 4)), with: .color(tone))
            }
            HStack {
                Text(rangeStart.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.current.locale)))
                Spacer()
                Text(window.resetsAt.map { L("重置 ", "Reset ") + $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.current.locale)) } ?? L("现在", "Now"))
            }.font(.system(size: 8)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel(L("\(localized(window.title))已用额度趋势，实线为观测历史，虚线为均速预测；缺失历史不补画", "\(localized(window.title)) usage trend. Solid: observed history. Dashed: average-rate forecast. Missing history is not filled in."))
    }
}
