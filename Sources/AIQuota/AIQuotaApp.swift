import AppKit
import SwiftUI
import Combine
import QuotaCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var store: QuotaStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panel: NSPanel!
    private var subscription: AnyCancellable?
    private var viewportSubscriptions: Set<AnyCancellable> = []
    private var feedbackSubscription: AnyCancellable?
    private let popoverViewport = DashboardViewport()
    private let panelViewport = DashboardViewport()
    private var screenObserver: NSObjectProtocol?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = QuotaStore()
        if CommandLine.arguments.contains("--check-codex") {
            Task {
                do {
                    let snapshot = try await store.codexClient.fetch()
                    print(String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!)
                    store.stop(); NSApp.terminate(nil)
                } catch { fputs("Codex check failed: \(error.localizedDescription)\n", stderr); store.stop(); exit(1) }
            }
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.toolTip = L("剩余额度 · CX: 5h = Codex 5 小时 / W = 每周 · CU: C = Cursor Models / O = Other Models · CL: 5h = Claude 5 小时 / W = 每周 · GM: 5h = Gemini 5 小时 / W = 每周 · ! 表示数据过期", "Remaining · CX: Codex 5h / weekly · CU: Cursor Models / Other Models · CL: Claude 5h / weekly · GM: Gemini 5h / weekly · ! means stale data")
        statusItem.button?.setAccessibilityLabel(L("AI Quota 额度详情", "AI Quota Details"))
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        let controller = NSHostingController(rootView: DashboardContainer(viewport: popoverViewport, dashboard: dashboard(floating: false)))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 416, height: 600), styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = "AI Quota"
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        let panelContent = NSHostingView(rootView: DashboardContainer(viewport: panelViewport, dashboard: dashboard(floating: true)))
        // Window dimensions follow measured content; an initial hosting minimum would prevent later collapse.
        panelContent.sizingOptions = []
        panel.contentView = panelContent
        panel.contentMinSize = .zero
        panel.delegate = self
        applyPin()
        panel.setFrameAutosaveName("QuotaFloatingPanel")
        let restored = panel.setFrameUsingName("QuotaFloatingPanel")
        if !restored, let screen = NSScreen.main { panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 390, y: screen.visibleFrame.maxY - 30)) }
        ensureVisible()
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.statusItem.button?.title = self.store.menuTitle; self.updateStatusLanguage(); self.resizePanel(); if self.popover.isShown { self.fitPopover() } }
        }
        feedbackSubscription = store.feedbackEvents.sink { [weak self] change in
            self?.animateStatusItem(change)
        }
        statusItem.button?.title = store.menuTitle
        if UserDefaults.standard.object(forKey: "showFloating") == nil || UserDefaults.standard.bool(forKey: "showFloating") { panel.orderFrontRegardless() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resizePanel(); self?.fitPopover() }
        }
        for viewport in [panelViewport, popoverViewport] {
            viewport.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizePanel(); self?.fitPopover() }
            }.store(in: &viewportSubscriptions)
        }
        resizePanel()
        store.start()
    }
    private func updateStatusLanguage() {
        statusItem.button?.toolTip = L("剩余额度 · CX: 5h = Codex 5 小时 / W = 每周 · CU: C = Cursor Models / O = Other Models · CL: 5h = Claude 5 小时 / W = 每周 · GM: 5h = Gemini 5 小时 / W = 每周 · ! 表示数据过期", "Remaining · CX: Codex 5h / weekly · CU: Cursor Models / Other Models · CL: Claude 5h / weekly · GM: Gemini 5h / weekly · ! means stale data")
        statusItem.button?.setAccessibilityLabel(L("AI Quota 额度详情", "AI Quota Details"))
    }
    private func animateStatusItem(_ change: QuotaChange) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.75 : 0.4
        animation.duration = 0.45
        animation.autoreverses = true
        animation.repeatCount = change.intensity == .major ? 3 : change.intensity == .large ? 2 : 1
        button.layer?.add(animation, forKey: "quotaChange")
    }
    private func dashboard(floating: Bool) -> DashboardView {
        DashboardView(store: store, floating: floating, toggleWindow: { [weak self] in self?.toggleWindow() }, togglePin: { [weak self] in self?.togglePin() }, chooseCodex: { [weak self] in self?.chooseCodex() })
    }
    private func resizePanel() {
        guard panel?.contentView != nil, let screen = panel.screen ?? NSScreen.main else { return }
        panelViewport.update(WindowBounds.dashboardLimit(in: screen.visibleFrame))
        let size = panelViewport.preferredSize
        if size.height > 100, abs(panel.frame.height - size.height) > 1 {
            let top = panel.frame.maxY
            // fullSizeContentView fills the frame; setContentSize would add the hidden title bar again.
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        }
        ensureVisible()
    }
    private func ensureVisible() {
        guard let panel, let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let frame = WindowBounds.contained(panel.frame, in: screen.visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
    private func fitPopover() {
        // Use the menu item's screen, which can differ from the main/floating-window screen.
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main,
              let view = popover.contentViewController?.view else { return }
        popoverViewport.update(WindowBounds.dashboardLimit(in: screen.visibleFrame))
        view.layoutSubtreeIfNeeded()
        let size = popoverViewport.preferredSize
        if size.width > 0, size.height > 0, popover.contentSize != size { popover.contentSize = size }
        if popover.isShown, let window = view.window {
            let frame = WindowBounds.contained(window.frame, in: screen.visibleFrame)
            if frame != window.frame { window.setFrame(frame, display: true) }
        }
    }
    func popoverDidShow(_ notification: Notification) { fitPopover() }
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            fitPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            fitPopover()
        }
    }
    private func toggleWindow() {
        if panel.isVisible { panel.orderOut(nil); UserDefaults.standard.set(false, forKey: "showFloating") }
        else { resizePanel(); ensureVisible(); panel.orderFrontRegardless(); UserDefaults.standard.set(true, forKey: "showFloating") }
    }
    private func togglePin() { store.pinned.toggle(); UserDefaults.standard.set(store.pinned, forKey: "pinned"); applyPin() }
    private func applyPin() {
        // Unpinned windows belong to their Space and participate in its transition.
        // All-Spaces/auxiliary behavior can otherwise keep a normal-level panel above a swipe.
        panel.isFloatingPanel = store.pinned
        panel.collectionBehavior = store.pinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.managed]
        panel.level = store.pinned ? .floating : .normal
    }
    private func chooseCodex() {
        popover.performClose(nil)
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.title = L("选择 Codex 可执行程序", "Choose Codex Executable"); picker.message = L("选择已安装的 codex 程序。", "Select the installed codex executable.")
        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK, let url = picker.url, FileManager.default.isExecutableFile(atPath: url.path) {
            UserDefaults.standard.set(url.path, forKey: "codexPath"); store.codexClient.stop(); store.refresh()
        }
    }
    func windowWillClose(_ notification: Notification) {
        if !terminating { UserDefaults.standard.set(false, forKey: "showFloating") }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard panel != nil else { return true }
        resizePanel(); ensureVisible(); panel.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "showFloating")
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main enum AIQuotaApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
