import SwiftUI
import QuotaCore

struct DashboardView: View {
    @ObservedObject var store: QuotaStore
    var floating: Bool
    var toggleWindow: () -> Void
    var togglePin: () -> Void
    var chooseCodex: () -> Void
    @State private var showingChanges = false
    private let accent = Color(red: 0.40, green: 0.86, blue: 0.73)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI QUOTA").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2.5).foregroundStyle(accent)

                }
                Spacer()
                Button(action: { store.toggleWatching() }) {
                    Text(store.watchSeconds > 0 ? L("◉ 密切关注 \(store.watchSeconds / 60):\(String(format: "%02d", store.watchSeconds % 60)) ×", "◉ Close Watch \(store.watchSeconds / 60):\(String(format: "%02d", store.watchSeconds % 60)) ×") : L("◎ 密切关注", "◎ Close Watch"))
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(store.watchSeconds > 0 ? accent : .secondary)
                        .padding(7).background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.10)))
                }.help(L("全部提供商立即刷新，此后每 10 秒刷新；再次点击停止。时长在更多菜单设置。", "Refresh all providers now, then every 10 seconds. Click again to stop. Set duration in More."))
                .accessibilityLabel(store.watchSeconds > 0 ? L("停止密切关注", "Stop Close Monitoring") : L("开启密切关注", "Start Close Monitoring"))
                if floating {
                    Button(action: togglePin) { Image(systemName: store.pinned ? "pin.fill" : "pin") }.help(store.pinned ? L("取消置顶", "Unpin") : L("保持置顶", "Keep on Top")).accessibilityLabel(store.pinned ? L("取消置顶", "Unpin") : L("保持置顶", "Keep on Top"))
                    Button(action: toggleWindow) { Image(systemName: "minus").frame(width: 32, height: 32).contentShape(Rectangle()) }.help(L("隐藏悬浮窗", "Hide Floating Window")).accessibilityLabel(L("隐藏悬浮窗", "Hide Floating Window"))
                } else {
                    Button(action: toggleWindow) { Image(systemName: "macwindow") }.help(L("显示或隐藏桌面悬浮窗", "Show or hide floating window")).accessibilityLabel(L("显示或隐藏桌面悬浮窗", "Show or hide floating window"))
                }
            }.buttonStyle(.plain)
            ForEach(store.providerOrder) { provider in
                VStack(spacing: 6) {
                    if store.arrangingProviders {
                        HStack {
                            Text(provider.title).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Button(action: { store.moveProvider(provider, by: -1) }) { Image(systemName: "arrow.up") }
                                .disabled(store.providerOrder.first == provider).accessibilityLabel(L("上移 \(provider.title)", "Move Up \(provider.title)"))
                            Button(action: { store.moveProvider(provider, by: 1) }) { Image(systemName: "arrow.down") }
                                .disabled(store.providerOrder.last == provider).accessibilityLabel(L("下移 \(provider.title)", "Move Down \(provider.title)"))
                        }.buttonStyle(.borderless)
                    }
                    providerCard(provider)
                }
            }
            if store.arrangingProviders {
                Button(L("完成排序", "Done Reordering")) { store.arrangingProviders = false }.buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                Circle().fill(store.refreshing ? Color.orange : accent).frame(width: 5, height: 5)
                Text(store.refreshing ? L("正在同步", "Syncing") : (store.watchSeconds > 0 ? L("密切关注中 · 每 10 秒同步", "Monitoring · sync every 10 seconds") : L("每分钟同步", "Sync every minute"))).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingChanges.toggle()
                    store.unreadChanges = false
                } label: {
                    Image(systemName: store.unreadChanges ? "clock.badge.exclamationmark" : "clock.arrow.circlepath")
                        .foregroundStyle(store.unreadChanges ? accent : Color.secondary)
                        .frame(width: 18, height: 18)
                }.accessibilityLabel(L("最近变化", "Recent Changes"))
                    .popover(isPresented: $showingChanges) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("最近变化", "Recent Changes")).font(.headline)
                            if store.recentChanges.isEmpty { Text(L("暂无变化记录", "No changes yet")).foregroundStyle(.secondary) }
                            ScrollView {
                                VStack(alignment: .leading, spacing: 9) {
                                    ForEach(store.recentChanges) { entry in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(L(entry.text, entry.englishText)).font(.system(size: 11))
                                            Text(entry.date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(store.language.locale))).font(.system(size: 9)).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }.padding(14).frame(width: 300, height: 240).preferredColorScheme(.dark)
                    }
                Button(action: { store.refresh() }) { Label(L("刷新", "Refresh"), systemImage: "arrow.clockwise") }.disabled(store.refreshing)
                Menu {
                    Text(L("语言", "Language"))
                    Button("\(store.language == .chinese ? "✓ " : "")简体中文") { store.language = .chinese }
                    Button("\(store.language == .english ? "✓ " : "")English") { store.language = .english }
                    Divider()
                    Button(store.arrangingProviders ? L("完成排序", "Done Reordering") : L("调整卡片顺序", "Reorder Cards")) { store.arrangingProviders.toggle() }
                    Divider()
                    Button(L("连接 Gemini 账号", "Connect Gemini Account")) { store.geminiClient.showLogin() }
                    Button(L("连接 Claude 账号", "Connect Claude Account")) { store.claudeClient.showLogin() }
                    if store.claudeOrganizations.count > 1 {
                        ForEach(store.claudeOrganizations) { organization in
                            Button(L("Claude 工作区：\(organization.name)", "Claude workspace: \(organization.name)")) { store.selectClaudeOrganization(organization.id) }
                                .disabled(store.claude.refreshing)
                        }
                    }
                    Button(L("连接 Cursor 账号", "Connect Cursor Account")) { store.cursorClient.showLogin() }
                    Button(L("打开 Codex", "Open Codex")) { openCodex() }
                    Button(L("选择 Codex 程序…", "Choose Codex Executable…"), action: chooseCodex)
                    Divider()
                    Toggle(L("音效（额度变化与关注开关）", "Sounds (quota changes and monitoring)"), isOn: $store.soundEnabled)
                    ForEach(QuotaSoundTheme.allCases, id: \.self) { theme in
                        Button(L("\(store.soundTheme == theme ? "✓ " : "")音色：\(localized(theme.title))", "\(store.soundTheme == theme ? "✓ " : "")Sound: \(localized(theme.title))")) {
                            store.soundTheme = theme
                        }
                    }
                    Button(L("预览：小幅减少 · −1%", "Preview: Small Decrease · −1%")) { store.previewFeedback(delta: -1) }
                    Button(L("预览：明显减少 · −3%", "Preview: Notable Decrease · −3%")) { store.previewFeedback(delta: -3) }
                    Button(L("预览：大幅恢复 · +20%", "Preview: Large Recovery · +20%")) { store.previewFeedback(delta: 20) }
                    Divider()
                    Text(L("密切关注时长 · 下次开启生效", "Monitoring duration · applies next time"))
                    ForEach(QuotaStore.watchDurationOptions, id: \.self) { minutes in
                        Button(L("\(store.watchDurationMinutes == minutes ? "✓ " : "")关注 \(minutes) 分钟", "\(store.watchDurationMinutes == minutes ? "✓ " : "")Watch \(minutes) min")) {
                            store.watchDurationMinutes = minutes
                        }
                    }
                    Divider()
                    Button(store.pinned ? L("取消悬浮窗置顶", "Unpin Floating Window") : L("悬浮窗置顶", "Pin Floating Window"), action: togglePin)
                    Button(L("显示 / 隐藏悬浮窗", "Show / Hide Floating Window"), action: toggleWindow)
                    Divider()
                    Button(L("退出 AI Quota", "Quit AI Quota")) { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(L("更多操作", "More"))
            }.font(.system(size: 11)).buttonStyle(.plain)
            if let error = store.historyError {
                Text(localized(error)).font(.system(size: 10)).foregroundStyle(.orange)
            }
            if store.gemini.snapshot == nil {
                Button(L("连接 Gemini 账号 →", "Connect Gemini Account →")) { store.geminiClient.showLogin() }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent).buttonStyle(.plain)
            }
            if store.claude.snapshot == nil {
                Button(L("连接 Claude 账号 →", "Connect Claude Account →")) { store.claudeClient.showLogin() }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent).buttonStyle(.plain)
            }
            if store.cursor.snapshot == nil {
                Button(L("连接 Cursor 账号 →", "Connect Cursor Account →")) { store.cursorClient.showLogin() }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent).buttonStyle(.plain)
            }
        }
        .padding(12).frame(maxWidth: .infinity)
        .preferredColorScheme(.dark)
        .environment(\.locale, store.language.locale)
    }
    private func providerCard(_ provider: QuotaProvider) -> some View {
        let state: ProviderState
        let symbol: String
        let tint: Color
        switch provider {
        case .codex: state = store.codex; symbol = "terminal"; tint = accent
        case .cursor: state = store.cursor; symbol = "cursorarrow"; tint = Color(red: 0.69, green: 0.67, blue: 1)
        case .claude: state = store.claude; symbol = "sparkle"; tint = Color(red: 0.90, green: 0.62, blue: 0.45)
        case .gemini: state = store.gemini; symbol = "sparkles"; tint = Color(red: 0.55, green: 0.72, blue: 1)
        }
        return ProviderCard(name: provider.title, symbol: symbol, tint: tint, state: state, now: store.now,
            isExpanded: !store.collapsedProviders.contains(provider.rawValue),
            toggleExpanded: { store.toggleCollapsed(provider) })
    }
    private func openCodex() {
        let urls = ["/Applications/ChatGPT.app", "/Applications/Codex.app"].map { URL(fileURLWithPath: $0) }
        if let url = urls.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
    }
}

struct ProviderCard: View {
    let name: String
    let symbol: String
    let tint: Color
    let state: ProviderState
    let now: Date
    let isExpanded: Bool
    var toggleExpanded: () -> Void
    @AppStorage("appLanguage") private var languageCode = AppLanguage.current.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var activeChange: QuotaChange? {
        guard let change = state.change, change.expiresAt > now else { return nil }
        return change
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    Text(name).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if let change = activeChange {
                        let delta = change.dominantDelta
                        Text(L("\(change.isPreview ? "预览 " : "")\(delta > 0 ? "+" : "")\(delta)%", "\(change.isPreview ? "Preview " : "")\(delta > 0 ? "+" : "")\(delta)%"))
                            .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1)
                            .foregroundStyle(delta > 0 ? Color.mint : Color(red: 1, green: 0.60, blue: 0.58))
                            .help(L("剩余额度变化（百分点）", "Remaining quota change (percentage points)"))
                            .accessibilityLabel(L("\(change.isPreview ? "效果预览" : "额度变化") \(delta) 个百分点", "\(change.isPreview ? "Effect preview" : "Quota change") \(delta) percentage points"))
                    } else {
                        Text(state.snapshot == nil ? L("未连接", "Not connected") : state.stale(at: now) ? L("数据过期", "Stale data") : L("剩余额度", "Remaining"))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(state.stale(at: now) ? Color.orange : .secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(L("\(isExpanded ? "折叠" : "展开") \(name)", "\(isExpanded ? "Collapse" : "Expand") \(name)"))
                .accessibilityValue(isExpanded ? L("已展开", "Expanded") : L("已折叠", "Collapsed"))
            if isExpanded {
                if let snapshot = state.snapshot {
                    ForEach(snapshot.windows) { window in
                        MetricView(window: window, history: state.history[window.id], sampledAt: snapshot.updatedAt,
                            now: now, stale: state.stale(at: now), change: activeChange)
                    }
                    if let note = snapshot.resetNote { Text(L("账期重置 · \(note)", "Billing reset · \(note)")).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }

                } else {
                    Text(state.refreshing ? L("正在读取额度…", "Loading quota…") : L("连接账号后显示真实余量", "Connect an account to see your quota"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
                }
            } else if let snapshot = state.snapshot {
                Text(snapshot.windows.map { "\(localized($0.title)): \(Int($0.remaining.rounded()))%" }.joined(separator: "  ·  "))
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(state.stale(at: now) ? Color.orange : tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = state.error { Text(localized(error)).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.62))
                .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
            LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
        .overlay {
            if let change = activeChange, now.timeIntervalSince(change.startedAt) < change.intensity.duration { QuotaChangeEffect(change: change).id(change.id) }
        }
    }
    private func resetText(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return L("重置时间已到 · 等待同步", "Reset due · waiting for sync") }
        let minutes = max(1, seconds / 60)
        if minutes >= 1440 { return L("\(minutes / 1440) 天 \((minutes % 1440) / 60) 小时后重置", "\(minutes / 1440) days \((minutes % 1440) / 60) hours until reset") }
        return L("\(minutes / 60) 小时 \(minutes % 60) 分钟后重置", "\(minutes / 60) hours \(minutes % 60) min until reset")
    }
}
