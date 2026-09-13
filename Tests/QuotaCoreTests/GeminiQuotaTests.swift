import XCTest
@testable import QuotaCore
final class GeminiQuotaTests: XCTestCase {
    func testWebUsageFractionKindsAndExactReset() throws {
        let data = Data("[2,[[4000,0.25,2,[[1800604800,500000000]]],[300,0.4,1,[[1800018000,0]]]],false]".utf8)
        let snapshot = try QuotaParser.gemini(data)
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [40, 25])
        XCTAssertEqual(snapshot.windows.map(\.title), ["5 小时额度", "每周额度"])
        XCTAssertEqual(snapshot.windows[0].cycleStartedAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertEqual(snapshot.windows[1].resetsAt, Date(timeIntervalSince1970: 1800604800.5))
    }
    func testMissingUnknownAndInvalidAreNotFullQuota() throws {
        XCTAssertThrowsError(try QuotaParser.gemini(Data("[2,[]]".utf8)))
        XCTAssertThrowsError(try QuotaParser.gemini(Data("[2,[[0,true,1]]]".utf8)))
        XCTAssertThrowsError(try QuotaParser.gemini(Data("[2,[[0,-0.1,1]]]".utf8)))
        XCTAssertThrowsError(try QuotaParser.gemini(Data("[2,[[0,0.1,1,[[\"bad\"]]]]]".utf8)))
        XCTAssertThrowsError(try QuotaParser.gemini(Data("[2,[[0,0.1,1],[0,0.2,1]]]".utf8)))
        let partial = try QuotaParser.gemini(Data("[2,[[0,0.2,2],[50,0,3]]]".utf8))
        XCTAssertEqual(partial.windows.count, 1)
        XCTAssertNil(partial.windows[0].cycleStartedAt)
    }
}
