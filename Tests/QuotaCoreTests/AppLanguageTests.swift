import XCTest
@testable import QuotaCore

final class AppLanguageTests: XCTestCase {
    func testSavedChoiceOverridesSystemAndInvalidPreferenceFallsBack() {
        XCTAssertEqual(AppLanguage.resolve(saved: "en", preferred: ["zh-Hans"]), .english)
        XCTAssertEqual(AppLanguage.resolve(saved: "zh-Hans", preferred: ["en-US"]), .chinese)
        XCTAssertEqual(AppLanguage.resolve(saved: "unknown", preferred: ["zh-Hant"]), .chinese)
        XCTAssertEqual(AppLanguage.resolve(saved: nil, preferred: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.resolve(saved: nil, preferred: []), .english)
    }
    func testDisplayTranslationPreservesStoredWindowAndUnknownText() throws {
        let window = QuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 30)
        let before = try JSONEncoder().encode(window)
        XCTAssertEqual(AppLanguage.english.display(window.title), "5-hour quota")
        XCTAssertEqual(AppLanguage.chinese.display(window.title), "5 小时额度")
        XCTAssertEqual(AppLanguage.english.display("12 小时额度"), "12-hour quota")
        XCTAssertEqual(AppLanguage.english.display("30 分钟额度"), "30-minute quota")
        XCTAssertEqual(AppLanguage.english.display("Some Workspace"), "Some Workspace")
        XCTAssertEqual(try JSONDecoder().decode(QuotaWindow.self, from: before), window)
    }
    func testErrorsAndPoolNamesHaveEnglishTranslations() {
        for value in ["每周额度", "Sonnet 每周", "Opus 每周", "正在验证上次数据",
                      "Claude 登录已失效，请重新连接", "Gemini 用量格式已变化",
                      "历史暂时无法保存，退出后可能丢失本次记录"] {
            let result = AppLanguage.english.display(value)
            XCTAssertNotEqual(result, value)
            XCTAssertNil(result.range(of: "\\p{Han}", options: .regularExpression))
            XCTAssertEqual(AppLanguage.chinese.display(value), value)
        }
    }
}
