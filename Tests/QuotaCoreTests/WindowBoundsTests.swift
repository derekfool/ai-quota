import CoreGraphics
import XCTest
@testable import QuotaCore

final class WindowBoundsTests: XCTestCase {
    func testOversizedPopoverStaysWithinSmallScreen() {
        let screen = CGRect(x: 0, y: 40, width: 1024, height: 660)
        let result = WindowBounds.contained(CGRect(x: 900, y: -180, width: 380, height: 980), in: screen)
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.maxX, screen.maxX - 8)
        XCTAssertLessThan(WindowBounds.dashboardLimit(in: screen).height, screen.height)
    }
    func testUsesSecondaryDisplayWithNegativeOrigin() {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 850)
        let result = WindowBounds.contained(CGRect(x: -170, y: 800, width: 360, height: 600), in: screen)
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.maxX, -8)
        XCTAssertEqual(result.maxY, screen.maxY - 8)
    }
    func testNormalWindowDoesNotMove() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 900, y: 100, width: 360, height: 650)
        XCTAssertEqual(WindowBounds.contained(frame, in: screen), frame)
    }
}
