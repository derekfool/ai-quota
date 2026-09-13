import XCTest
import JavaScriptCore
@testable import QuotaCore

final class GeminiWebCaptureTests: XCTestCase {
    func context(origin: String = "https://gemini.google.com") -> JSContext {
        let context = JSContext()!
        context.evaluateScript("""
        var window = this;
        var location = { origin: '\(origin)', href: '\(origin)/usage' };
        var opened = 0;
        function URL(text, base) {
            this.origin = text.startsWith('https://other.example') ? 'https://other.example' : location.origin;
            this.pathname = text.includes('/batchexecute') ? '/_/BardChatUi/data/batchexecute' : '/unrelated';
            this.searchParams = { get: function() { return text.includes('rpcids=jSf9Qc') ? 'jSf9Qc' : 'other'; } };
        }
        function XMLHttpRequest() { this.listeners = []; this.status = 200; this.responseType = ''; }
        XMLHttpRequest.prototype.addEventListener = function(name, action) { this.listeners.push(action); };
        XMLHttpRequest.prototype.open = function() { opened++; };
        XMLHttpRequest.prototype.fire = function(text) { this.responseText = text; for (var action of this.listeners) action.call(this); };
        """)
        context.evaluateScript(GeminiWebCapture.script)
        return context
    }
    func testOnlyUsagePayloadIsCapturedAndOriginalRequestIsPreserved() throws {
        let context = context()
        let payload = "[2,[[500,0.4,1,[[1800018000,0]]]]]"
        let row: [Any] = ["wrb.fr", "jSf9Qc", payload]
        let data = try JSONSerialization.data(withJSONObject: [row])
        context.setObject(")]}'\n\n100\n" + String(decoding: data, as: UTF8.self) + "\n", forKeyedSubscript: "fixture" as NSString)
        context.evaluateScript("var req = new XMLHttpRequest(); req.open('POST', '/_/BardChatUi/data/batchexecute?rpcids=jSf9Qc'); req.fire(fixture);")
        XCTAssertNil(context.exception)
        XCTAssertEqual(context.evaluateScript("window.__aiQuotaGeminiUsage.payload")?.toString(), payload)
        XCTAssertEqual(context.evaluateScript("opened")?.toInt32(), 1)
        XCTAssertGreaterThan(context.evaluateScript("window.__aiQuotaGeminiUsage.receivedAt")!.toDouble(), 0)
    }
    func testUnrelatedTrafficErrorsAndMalformedFramesCannotUpdateUsage() {
        let context = context()
        context.evaluateScript("var r = new XMLHttpRequest(); r.open('POST', '/unrelated'); r.fire('private');")
        XCTAssertTrue(context.evaluateScript("window.__aiQuotaGeminiUsage === null")!.toBool())
        context.evaluateScript("r = new XMLHttpRequest(); r.open('POST', '/_/BardChatUi/data/batchexecute?rpcids=jSf9Qc'); r.status = 403; r.fire('[]');")
        XCTAssertTrue(context.evaluateScript("window.__aiQuotaGeminiUsage === null")!.toBool())
        context.evaluateScript("r.status = 200; r.fire('[malformed');")
        XCTAssertNil(context.exception)
        XCTAssertTrue(context.evaluateScript("window.__aiQuotaGeminiUsage === null")!.toBool())
        let foreign = self.context(origin: "https://accounts.google.com")
        XCTAssertTrue(foreign.evaluateScript("typeof window.__aiQuotaGeminiUsage === 'undefined'")!.toBool())
    }
}
