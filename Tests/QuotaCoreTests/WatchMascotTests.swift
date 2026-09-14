import XCTest
@testable import QuotaCore

final class WatchMascotTests: XCTestCase {
    func testLyingCatMovesOnlyAfterOcclusionDelay() {
        XCTAssertEqual(WatchMascot.lying.visibility(elapsed: 0.05, exiting: true), 1)
        XCTAssertLessThan(WatchMascot.lying.visibility(elapsed: 0.12, exiting: true), 1)
        XCTAssertEqual(WatchMascot.lying.visibility(elapsed: 0.28, exiting: true), 0, accuracy: 0.00001)
    }
    func testAxisFollowsRotatedNoseBellyVector() {
        let axis = WatchMascot.blank.axis
        XCTAssertEqual(hypot(axis.x, axis.y), 1, accuracy: 0.00001)
        let x = axis.x * cos(0.32) - axis.y * sin(0.32)
        let y = axis.x * sin(0.32) + axis.y * cos(0.32)
        XCTAssertEqual(x / y, -0.005 / 0.36, accuracy: 0.00001)
    }
    func testAllPosesFinishAndBlinkRepeats() {
        for kind in WatchMascot.allCases {
            XCTAssertEqual(kind.visibility(elapsed: 0, exiting: false), 0)
            XCTAssertEqual(kind.visibility(elapsed: 0.3, exiting: false), 1)
            XCTAssertEqual(kind.visibility(elapsed: 1, exiting: true), 0)
            XCTAssertEqual(kind.blink(at: 3.9), 1, accuracy: 0.00001)
            XCTAssertEqual(kind.blink(at: 10.2), 1, accuracy: 0.00001)
        }
    }
}
