import AppKit
import WebKit
import QuotaCore

@MainActor final class GeminiClient: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    private var loginWindow: NSWindow?
    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]
    private var navigationError: String?
    private var lastAcceptedAt = Date.distantPast
    private let spendingURL = URL(string: "https://gemini.google.com/usage?hl=en")!

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(WKUserScript(source: GeminiWebCapture.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 760), configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
    }
    func fetch() async throws -> QuotaSnapshot {
        navigationError = nil
        guard popupWindows.isEmpty else { throw QuotaError.invalidData("请在 Gemini 登录弹窗完成验证") }
        let visible = loginWindow?.isVisible == true
        let requestedAt = Date()
        if !visible {
            webView.load(URLRequest(url: spendingURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
        }
        for _ in 0..<50 {
            if let navigationError { throw QuotaError.invalidData(navigationError) }
            if webView.url?.host == "accounts.google.com", !webView.isLoading {
                throw QuotaError.invalidData("请在 Gemini 官方窗口完成登录")
            }
            if webView.url?.host == "gemini.google.com", let result = try? await webView.evaluateJavaScript(Self.readScript),
               let response = result as? [String: Any], let milliseconds = response["receivedAt"] as? Double,
               let body = response["payload"] as? String {
                let receivedAt = Date(timeIntervalSince1970: milliseconds / 1000)
                if receivedAt > lastAcceptedAt, visible || receivedAt >= requestedAt {
                    let snapshot = try QuotaParser.gemini(Data(body.utf8), now: receivedAt)
                    lastAcceptedAt = receivedAt
                    return snapshot
                }
            }
            if visible, !webView.isLoading { throw QuotaError.invalidData("完成 Gemini 登录后关闭窗口，再刷新额度") }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw QuotaError.invalidData("Gemini 用量页未返回新数据，请连接账号或稍后刷新")
    }
    // Observe only the official usage response. Google performs its own request and authentication;
    // we do not read cookies, request bodies, chat responses, or account tokens.
    static let readScript = #"""
    (() => {
        if (location.origin !== 'https://gemini.google.com' || !location.pathname.endsWith('/usage')) return null;
        return window.__aiQuotaGeminiUsage || null;
    })();
    """#
    func refreshLanguage() {
        loginWindow?.title = L("连接 Gemini", "Connect Gemini")
        for window in popupWindows.values { window.title = L("Gemini 登录验证", "Gemini Sign-in Verification") }
    }
    func showLogin() {
        if loginWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("连接", "Connect") + " Gemini · gemini.google.com"
            window.contentView = webView; window.isReleasedWhenClosed = false; window.delegate = self
            window.center(); loginWindow = window
        }
        loginWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let popup = popupWindows.values.first {
            popup.makeKeyAndOrderFront(nil)
        } else {
            // A failed old login may have left the main view stranded on Google's callback page.
            webView.load(URLRequest(url: spendingURL))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView {
            loginWindow?.title = L("连接 Gemini · \(webView.url?.host ?? "") · 登录后关闭窗口并刷新额度", "Connect Gemini · \(webView.url?.host ?? "") · Close after signing in, then refresh")
        } else {
            popupWindows[ObjectIdentifier(webView)]?.title = L("Gemini 登录验证 · \(webView.url?.host ?? "")", "Gemini Sign-in Verification · \(webView.url?.host ?? "")")
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { record(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { record(error) }
    private func record(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { navigationError = "Gemini 网络连接失败，请稍后刷新" } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { navigationError = "Gemini 页面已暂停，请重新刷新" }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let scheme = navigationAction.request.url?.scheme,
              scheme == "https" || scheme == "about" else { return nil }
        // WebKit's supplied configuration preserves window.opener and OAuth postMessage.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 720), configuration: configuration)
        popup.navigationDelegate = self; popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("Gemini 登录验证", "Gemini Sign-in Verification")
        window.contentView = popup; window.delegate = self; window.isReleasedWhenClosed = false
        popupWindows[ObjectIdentifier(popup)] = window
        window.center(); window.makeKeyAndOrderFront(nil)
        return popup
    }
    func webViewDidClose(_ webView: WKWebView) {
        popupWindows[ObjectIdentifier(webView)]?.close()
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === loginWindow {
            let windows = Array(popupWindows.values)
            for popup in windows { popup.close() }
        } else if let key = popupWindows.first(where: { $0.value === window })?.key {
            popupWindows.removeValue(forKey: key)
            loginWindow?.makeKeyAndOrderFront(nil)
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
    }
}
