import AppKit
import WebKit
import QuotaCore

@MainActor final class ClaudeClient: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    struct Organization: Identifiable {
        let id: String
        let name: String
    }
    private(set) var organizations: [Organization] = []
    var selectedOrganization: String {
        get { UserDefaults.standard.string(forKey: "claudeOrganization") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "claudeOrganization") }
    }
    private var loginWindow: NSWindow?
    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]
    private var navigationError: String?
    private let spendingURL = URL(string: "https://claude.ai/settings/usage")!

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 760), configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
    }
    func fetch() async throws -> QuotaSnapshot {
        navigationError = nil
        guard popupWindows.isEmpty else { throw QuotaError.invalidData("请在 Claude 登录弹窗完成验证") }
        // Keep this origin alive: reloading a hidden dashboard can stall its client-side rendering.
        if webView.url == nil { webView.load(URLRequest(url: spendingURL, timeoutInterval: 20)) }
        var ready = false
        for _ in 0..<40 {
            if let navigationError { throw QuotaError.invalidData(navigationError) }
            if let host = webView.url?.host, ["accounts.google.com", "appleid.apple.com"].contains(host), !webView.isLoading {
                throw QuotaError.invalidData("请在 Claude 官方窗口完成登录")
            }
            if webView.url?.host == "claude.ai", webView.url?.path == "/login", !webView.isLoading {
                throw QuotaError.invalidData("请在 Claude 官方窗口完成登录")
            }
            if webView.url?.scheme == "https", webView.url?.host == "claude.ai", !webView.isLoading, webView.url?.path != "/login" { ready = true; break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        guard ready else { throw QuotaError.invalidData("Claude 页面连接超时，请打开官方页面后重试") }
        // Same-origin fetch keeps HTTP-only cookies inside WebKit; no credentials leave its store.
        let result: Any?
        do { result = try await webView.callAsyncJavaScript(Self.usageScript, arguments: ["selectedOrg": selectedOrganization], in: nil, contentWorld: .page) }
        catch { throw QuotaError.invalidData("Claude 用量请求失败，请稍后刷新") }
        guard let response = result as? [String: Any], let status = response["status"] as? Int else {
            throw QuotaError.invalidData("Claude 返回了无法识别的响应")
        }
        if let list = response["organizations"] as? [[String: String]] {
            organizations = list.compactMap { item in
                guard let id = item["id"], let name = item["name"] else { return nil }
                return Organization(id: id, name: name)
            }
        }
        switch status {
        case 200:
            guard let body = response["body"] as? String else { throw QuotaError.invalidData("Claude 未返回用量数据") }
            return try QuotaParser.claude(Data(body.utf8))
        case 409: throw QuotaError.invalidData("请在更多菜单选择 Claude 工作区")
        case 401: throw QuotaError.invalidData("Claude 登录已失效，请重新连接")
        case 403: throw QuotaError.invalidData("Claude 页面需要验证或拒绝读取，请打开官方用量页检查")
        case 429: throw QuotaError.invalidData("Claude 暂时限制刷新频率，请稍后重试")
        default: throw QuotaError.invalidData("Claude 用量读取失败，请稍后重试")
        }
    }
    private static let usageScript = #"""
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 12000);
    const options = { credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: abort.signal };
    try {
        const orgResponse = await fetch('/api/organizations', options);
        if (!orgResponse.ok) return { status: orgResponse.status };
        const raw = await orgResponse.json();
        if (!Array.isArray(raw)) return { status: 0 };
        const organizations = raw.filter(o => typeof o.uuid === 'string' &&
            (!Array.isArray(o.capabilities) || o.capabilities.includes('chat')))
            .map(o => ({ id: o.uuid, name: typeof o.name === 'string' ? o.name : 'Claude 工作区' }));
        const selected = organizations.find(o => o.id === selectedOrg) ||
            (organizations.length === 1 ? organizations[0] : null);
        if (!selected) return { status: 409, organizations };
        const response = await fetch('/api/organizations/' + encodeURIComponent(selected.id) + '/usage', options);
        return { status: response.status, organizations, body: response.ok ? await response.text() : '' };
    } catch (_) {
        return { status: 0 };
    } finally {
        clearTimeout(timeout);
    }
    """#
    func refreshLanguage() {
        loginWindow?.title = L("连接 Claude", "Connect Claude")
        for window in popupWindows.values { window.title = L("Claude 登录验证", "Claude Sign-in Verification") }
    }
    func showLogin() {
        if loginWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("连接", "Connect") + " Claude · claude.ai"
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
            loginWindow?.title = L("连接 Claude · \(webView.url?.host ?? "") · 登录后关闭窗口并刷新额度", "Connect Claude · \(webView.url?.host ?? "") · Close after signing in, then refresh")
        } else {
            popupWindows[ObjectIdentifier(webView)]?.title = L("Claude 登录验证 · \(webView.url?.host ?? "")", "Claude Sign-in Verification · \(webView.url?.host ?? "")")
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { record(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { record(error) }
    private func record(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { navigationError = "Claude 网络连接失败，请稍后刷新" } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { navigationError = "Claude 页面已暂停，请重新刷新" }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let scheme = navigationAction.request.url?.scheme,
              scheme == "https" || scheme == "about" else { return nil }
        // WebKit's supplied configuration preserves window.opener and OAuth postMessage.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 720), configuration: configuration)
        popup.navigationDelegate = self; popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("Claude 登录验证", "Claude Sign-in Verification")
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
