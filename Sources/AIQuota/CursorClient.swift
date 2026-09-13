import AppKit
import WebKit
import QuotaCore

@MainActor final class CursorClient: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    private var loginWindow: NSWindow?
    private var navigationError: String?
    private let spendingURL = URL(string: "https://cursor.com/dashboard/spending")!

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 760), configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
    }
    func fetch() async throws -> QuotaSnapshot {
        navigationError = nil
        // Keep this origin alive: reloading a hidden dashboard can stall its client-side rendering.
        if webView.url == nil { webView.load(URLRequest(url: spendingURL, timeoutInterval: 20)) }
        var ready = false
        for _ in 0..<40 {
            if let navigationError { throw QuotaError.invalidData(navigationError) }
            if let host = webView.url?.host, ["authenticator.cursor.sh", "authenticate.cursor.sh", "accounts.google.com", "github.com", "appleid.apple.com"].contains(host), !webView.isLoading {
                throw QuotaError.invalidData("请在 Cursor 官方窗口完成登录")
            }
            if webView.url?.scheme == "https", webView.url?.host == "cursor.com", !webView.isLoading { ready = true; break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        guard ready else { throw QuotaError.invalidData("Cursor 页面连接超时，请打开官方页面后重试") }
        // Same-origin fetch keeps HTTP-only cookies inside WebKit; no credentials leave its store.
        let result: Any?
        do { result = try await webView.callAsyncJavaScript(Self.usageScript, arguments: [:], in: nil, contentWorld: .page) }
        catch { throw QuotaError.invalidData("Cursor 用量请求失败，请稍后刷新") }
        guard let response = result as? [String: Any], let status = response["status"] as? Int else {
            throw QuotaError.invalidData("Cursor 返回了无法识别的响应")
        }
        switch status {
        case 200:
            guard let body = response["body"] as? String else { throw QuotaError.invalidData("Cursor 未返回用量数据") }
            return try QuotaParser.cursorSummary(Data(body.utf8))
        case 401: throw QuotaError.invalidData("Cursor 登录已失效，请重新连接")
        case 403: throw QuotaError.invalidData("Cursor 拒绝读取，请打开官方用量页检查")
        case 429: throw QuotaError.invalidData("Cursor 暂时限制刷新频率，请稍后重试")
        default: throw QuotaError.invalidData("Cursor 用量读取失败，请稍后重试")
        }
    }
    private static let usageScript = #"""
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 8000);
    try {
        const response = await fetch('/api/usage-summary', {
            credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: abort.signal
        });
        return { status: response.status, body: response.ok ? await response.text() : '' };
    } catch (_) {
        return { status: 0, body: '' };
    } finally {
        clearTimeout(timeout);
    }
    """#
    func refreshLanguage() {
        loginWindow?.title = L("连接 Cursor", "Connect Cursor")
    }
    func showLogin() {
        if loginWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("连接", "Connect") + " Cursor · cursor.com"
            window.contentView = webView; window.isReleasedWhenClosed = false; window.delegate = self
            window.center(); loginWindow = window
        }
        loginWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if webView.url == nil || webView.url?.host == "cursor.com" { webView.load(URLRequest(url: spendingURL)) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loginWindow?.title = L("连接 Cursor · \(webView.url?.host ?? "") · 登录后关闭窗口并刷新额度", "Connect Cursor · \(webView.url?.host ?? "") · Close after signing in, then refresh")
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { record(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { record(error) }
    private func record(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { navigationError = "Cursor 网络连接失败，请稍后刷新" } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { navigationError = "Cursor 页面已暂停，请重新刷新" }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
    }
}
