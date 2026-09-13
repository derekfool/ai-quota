import XCTest
@testable import QuotaCore

final class ProviderOrderTests: XCTestCase {
    func testSavedOrderRemovesUnknownDuplicatesAndKeepsEveryProvider() {
        XCTAssertEqual(ProviderOrder.normalized(["claude", "unknown", "claude", "codex"]), [.claude, .codex, .cursor, .gemini])
        XCTAssertEqual(ProviderOrder.normalized([]), [.codex, .cursor, .claude, .gemini])
    }
    func testMovesKeepIdentityAndRespectEnds() {
        let order: [QuotaProvider] = [.codex, .cursor, .claude]
        XCTAssertEqual(ProviderOrder.moving(.claude, by: -1, in: order), [.codex, .claude, .cursor])
        XCTAssertEqual(ProviderOrder.moving(.codex, by: 1, in: order), [.cursor, .codex, .claude])
        XCTAssertEqual(ProviderOrder.moving(.codex, by: -1, in: order), order)
        XCTAssertEqual(ProviderOrder.moving(.claude, by: 1, in: order), order)
    }
}
