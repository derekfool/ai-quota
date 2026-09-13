import AppKit
import Combine
import QuotaCore

struct ProviderState {
    var snapshot: QuotaSnapshot?
    var error: String?
    var refreshing = false
    var schedule = RefreshSchedule()
    var change: QuotaChange?
    var history: [String: UsageHistorySummary] = [:]
    func stale(at now: Date = Date()) -> Bool { error != nil || (snapshot?.isStale(at: now) ?? true) }
    func shortValue(for title: String) -> String {
        guard let window = snapshot?.windows.first(where: { $0.title == title }) else { return "—" }
        return "\(Int(window.remaining.rounded()))%\(stale() ? "!" : "")"
    }
}


struct RecentQuotaChange: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
    let englishText: String
}

@MainActor final class QuotaStore: ObservableObject {
    @Published var language = AppLanguage.current {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            claudeClient.refreshLanguage(); cursorClient.refreshLanguage(); geminiClient.refreshLanguage()
        }
    }
    @Published var recentChanges: [RecentQuotaChange] = []
    @Published var unreadChanges = false
    @Published var arrangingProviders = false
    @Published var providerOrder = ProviderOrder.normalized(UserDefaults.standard.stringArray(forKey: "providerOrder") ?? []) {
        didSet { UserDefaults.standard.set(providerOrder.map(\.rawValue), forKey: "providerOrder") }
    }
    func moveProvider(_ provider: QuotaProvider, by offset: Int) {
        providerOrder = ProviderOrder.moving(provider, by: offset, in: providerOrder)
    }
    @Published var codex = ProviderState()
    @Published var cursor = ProviderState()
    @Published var claude = ProviderState()
    @Published var gemini = ProviderState()
    @Published var historyError: String?
    private var history = QuotaHistory()
    private var historyWritable = true
    private var lastHistorySummaryAt = Date.distantPast
    private let historyURL: URL
    @Published var claudeOrganizations: [ClaudeClient.Organization] = []
    @Published var collapsedProviders = Set(UserDefaults.standard.stringArray(forKey: "collapsedProviders") ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedProviders), forKey: "collapsedProviders") }
    }
    func toggleCollapsed(_ provider: QuotaProvider) {
        if !collapsedProviders.insert(provider.rawValue).inserted { collapsedProviders.remove(provider.rawValue) }
    }
    func selectClaudeOrganization(_ id: String) {
        guard !claude.refreshing else { return }
        claudeClient.selectedOrganization = id
        claude.snapshot = nil; claude.error = nil; claude.change = nil
        claudeChanges = QuotaChangeTracker()
        history.clear(provider: "claude"); claude.history = [:]; persistHistory()
        persist()
        refresh(.claude, at: Date())
    }
    @Published var now = Date()
    @Published var pinned = UserDefaults.standard.bool(forKey: "pinned")
    @Published var soundEnabled = UserDefaults.standard.object(forKey: "quotaSoundEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "quotaSoundEnabled")
            if !soundEnabled { feedback.stop() }
        }
    }
    @Published var soundTheme = QuotaSoundTheme(rawValue: UserDefaults.standard.string(forKey: "quotaSoundTheme") ?? "") ?? .handpan {
        didSet {
            UserDefaults.standard.set(soundTheme.rawValue, forKey: "quotaSoundTheme")
            feedback.stop()
        }
    }
    static let watchDurationOptions = [1, 5, 10, 30]
    @Published var watchDurationMinutes: Int = {
        let saved = UserDefaults.standard.integer(forKey: "watchDurationMinutes")
        return watchDurationOptions.contains(saved) ? saved : 10
    }() {
        didSet { UserDefaults.standard.set(watchDurationMinutes, forKey: "watchDurationMinutes") }
    }
    private var codexChanges = QuotaChangeTracker()
    private var cursorChanges = QuotaChangeTracker()
    private var claudeChanges = QuotaChangeTracker()
    private var geminiChanges = QuotaChangeTracker()
    private let feedback = QuotaFeedback()
    let feedbackEvents = PassthroughSubject<QuotaChange, Never>()
    let codexClient = CodexClient()
    let cursorClient = CursorClient()
    let claudeClient = ClaudeClient()
    let geminiClient = GeminiClient()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let cacheURL: URL
    var menuTitle: String {
        providerOrder.map { provider in
            switch provider {
            case .codex: return "CX 5h \(codex.shortValue(for: "5 小时额度")) W \(codex.shortValue(for: "每周额度"))"
            case .cursor: return "CU C \(cursor.shortValue(for: "Cursor Models")) O \(cursor.shortValue(for: "Other Models"))"
            case .claude: return "CL 5h \(claude.shortValue(for: "5 小时额度")) W \(claude.shortValue(for: "每周额度"))"
            case .gemini: return "GM 5h \(gemini.shortValue(for: "5 小时额度")) W \(gemini.shortValue(for: "每周额度"))"
            }
        }.joined(separator: "  ·  ")
    }
    var refreshing: Bool { codex.refreshing || cursor.refreshing || claude.refreshing || gemini.refreshing }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AIQuota")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("quota-cache.json")
        historyURL = directory.appendingPathComponent("quota-history.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do {
                let saved = try JSONDecoder().decode(QuotaHistory.self, from: Data(contentsOf: historyURL))
                guard saved.version == 1 else { throw QuotaError.invalidData("历史版本不兼容") }
                history = saved
            } catch {
                historyWritable = false
                historyError = "旧历史无法读取，原文件已保留；本次历史仅保存在内存"
            }
        }
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([String: QuotaSnapshot].self, from: data) {
            codex.snapshot = saved["codex"]; cursor.snapshot = saved["cursor"]; claude.snapshot = saved["claude"]; gemini.snapshot = saved["gemini"]
            if codex.snapshot != nil { codex.error = "正在验证上次数据" }
            if cursor.snapshot != nil { cursor.error = "正在验证上次数据" }
            if claude.snapshot != nil { claude.error = "正在验证上次数据" }
            if gemini.snapshot != nil { gemini.error = "正在验证上次数据" }
            for provider in QuotaProvider.allCases {
                if let snapshot = saved[provider.rawValue] { updateHistorySummary(snapshot, provider: provider) }
            }
        }
    }
    func start() {
        refresh()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.now = Date()
                self.tick()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
    }
    func tick() {
        let time = now
        if time.timeIntervalSince(lastHistorySummaryAt) >= 60 {
            lastHistorySummaryAt = time
            for (provider, snapshot) in [(QuotaProvider.codex, codex.snapshot), (.cursor, cursor.snapshot), (.claude, claude.snapshot), (.gemini, gemini.snapshot)] {
                if let snapshot { updateHistorySummary(snapshot, provider: provider, at: time) }
            }
        }
        if let change = codex.change, change.expiresAt <= time { codex.change = nil }
        if let change = cursor.change, change.expiresAt <= time { cursor.change = nil }
        if let change = claude.change, change.expiresAt <= time { claude.change = nil }
        if let change = gemini.change, change.expiresAt <= time { gemini.change = nil }
        if codex.schedule.takeDueRefresh(at: time, requestInFlight: codex.refreshing) { refresh(.codex, at: time) }
        if cursor.schedule.takeDueRefresh(at: time, requestInFlight: cursor.refreshing) { refresh(.cursor, at: time) }
        if claude.schedule.takeDueRefresh(at: time, requestInFlight: claude.refreshing) { refresh(.claude, at: time) }
        if gemini.schedule.takeDueRefresh(at: time, requestInFlight: gemini.refreshing) { refresh(.gemini, at: time) }
    }
    var watchSeconds: Int { codex.schedule.secondsRemaining(at: now) }
    func toggleWatching() {
        let time = Date()
        now = time
        let stopping = watchSeconds > 0
        if soundEnabled { feedback.playFocus(starting: !stopping) }
        if stopping {
            codex.schedule.stopWatching(at: time); cursor.schedule.stopWatching(at: time)
            claude.schedule.stopWatching(at: time); gemini.schedule.stopWatching(at: time)
        } else {
            codex.schedule.startWatching(at: time, durationMinutes: watchDurationMinutes)
            cursor.schedule.startWatching(at: time, durationMinutes: watchDurationMinutes)
            claude.schedule.startWatching(at: time, durationMinutes: watchDurationMinutes)
            gemini.schedule.startWatching(at: time, durationMinutes: watchDurationMinutes)
        }
        tick()
    }
    func state(for provider: QuotaProvider) -> ProviderState {
        switch provider { case .codex: return codex; case .cursor: return cursor; case .claude: return claude; case .gemini: return gemini }
    }
    func refresh() {
        let time = Date()
        now = time
        refresh(.codex, at: time)
        refresh(.cursor, at: time)
        refresh(.claude, at: time)
        refresh(.gemini, at: time)
    }
    private func refresh(_ provider: QuotaProvider, at time: Date) {
        switch provider {
        case .codex:
            guard !codex.refreshing else { return }
            codex.schedule.recordRefresh(at: time)
            codex.refreshing = true
            Task {
                defer { codex.refreshing = false; persist() }
                do {
                    let snapshot = try await codexClient.fetch()
                    // Complete the UI clock tick before publishing a newer locally timestamped sample.
                    now = Date()
                    codex.snapshot = snapshot; codex.error = nil
                    recordHistory(snapshot, provider: .codex)
                    if let change = codexChanges.accept(snapshot) { codex.change = change; announce(change, provider: .codex) }
                }
                catch { codex.error = error.localizedDescription }
            }
        case .cursor:
            guard !cursor.refreshing else { return }
            cursor.schedule.recordRefresh(at: time)
            cursor.refreshing = true
            Task {
                defer { cursor.refreshing = false; persist() }
                do {
                    let snapshot = try await cursorClient.fetch()
                    // Complete the UI clock tick before publishing a newer locally timestamped sample.
                    now = Date()
                    cursor.snapshot = snapshot; cursor.error = nil
                    recordHistory(snapshot, provider: .cursor)
                    if let change = cursorChanges.accept(snapshot) { cursor.change = change; announce(change, provider: .cursor) }
                }
                catch { cursor.error = error.localizedDescription }
            }
        case .claude:
            guard !claude.refreshing else { return }
            claude.schedule.recordRefresh(at: time)
            claude.refreshing = true
            Task {
                defer { claude.refreshing = false; claudeOrganizations = claudeClient.organizations; persist() }
                do {
                    let snapshot = try await claudeClient.fetch()
                    // Complete the UI clock tick before publishing a newer locally timestamped sample.
                    now = Date()
                    claude.snapshot = snapshot; claude.error = nil
                    recordHistory(snapshot, provider: .claude)
                    if let change = claudeChanges.accept(snapshot) { claude.change = change; announce(change, provider: .claude) }
                }
                catch { claude.error = error.localizedDescription }
            }
        case .gemini:
            guard !gemini.refreshing else { return }
            gemini.schedule.recordRefresh(at: time)
            gemini.refreshing = true
            Task {
                defer { gemini.refreshing = false; persist() }
                do {
                    let snapshot = try await geminiClient.fetch()
                    // Complete the UI clock tick before publishing a newer locally timestamped sample.
                    now = Date()
                    gemini.snapshot = snapshot; gemini.error = nil
                    recordHistory(snapshot, provider: .gemini)
                    if let change = geminiChanges.accept(snapshot) { gemini.change = change; announce(change, provider: .gemini) }
                } catch { gemini.error = error.localizedDescription }
            }
        }
    }
    private func announce(_ change: QuotaChange, provider: QuotaProvider) {
        let snapshot = state(for: provider).snapshot
        let entries = change.deltas.keys.sorted().map { id in
            let delta = change.deltas[id]!
            let window = snapshot?.windows.first { $0.id == id }
            let values = window.map { "\(Int($0.remaining.rounded()) - delta)% → \(Int($0.remaining.rounded()))%" } ?? "\(delta)%"
            return RecentQuotaChange(date: change.startedAt,
                text: "\(change.isPreview ? "预览 · " : "")\(provider.title) · \(window?.title ?? "额度")  \(values)（\(delta > 0 ? "+" : "")\(delta)%）",
                englishText: "\(change.isPreview ? "Preview · " : "")\(provider.title) · \(AppLanguage.english.display(window?.title ?? "额度"))  \(values) (\(delta > 0 ? "+" : "")\(delta)%)")
        }
        recentChanges = Array((entries + recentChanges).prefix(30))
        unreadChanges = true
        feedbackEvents.send(change)
        if soundEnabled { feedback.play(change, theme: soundTheme) }
    }
    func previewFeedback(delta: Int) {
        let change = QuotaChange(deltas: [codex.snapshot?.windows.first?.id ?? "preview": delta], isPreview: true)
        codex.change = change
        announce(change, provider: .codex)
    }
    private func persist() {
        var snapshots: [String: QuotaSnapshot] = [:]
        snapshots["codex"] = codex.snapshot; snapshots["cursor"] = cursor.snapshot; snapshots["claude"] = claude.snapshot; snapshots["gemini"] = gemini.snapshot
        if let data = try? JSONEncoder().encode(snapshots) { try? data.write(to: cacheURL, options: .atomic) }
    }
    private func recordHistory(_ snapshot: QuotaSnapshot, provider: QuotaProvider) {
        history.record(snapshot, provider: provider.rawValue)
        updateHistorySummary(snapshot, provider: provider)
        persistHistory()
    }
    private func updateHistorySummary(_ snapshot: QuotaSnapshot, provider: QuotaProvider, at time: Date = Date()) {
        let summaries = Dictionary(uniqueKeysWithValues: snapshot.windows.map {
            ($0.id, history.summary(provider: provider.rawValue, window: $0, at: time))
        })
        switch provider {
        case .codex: codex.history = summaries
        case .cursor: cursor.history = summaries
        case .claude: claude.history = summaries
        case .gemini: gemini.history = summaries
        }
    }
    private func persistHistory() {
        guard historyWritable else { return }
        do { try JSONEncoder().encode(history).write(to: historyURL, options: .atomic); historyError = nil }
        catch { historyError = "历史暂时无法保存，退出后可能丢失本次记录" }
    }
    func stop() {
        timer?.invalidate(); codexClient.stop(); feedback.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
