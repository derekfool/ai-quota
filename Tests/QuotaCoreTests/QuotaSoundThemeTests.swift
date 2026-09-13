import XCTest
import AppKit
@testable import QuotaCore

final class QuotaSoundThemeTests: XCTestCase {
    func testThresholdsAndRecoveryOnlyCelebration() {
        for sign in [-1, 1] {
            for (points, tier) in [(2, ChangeIntensity.small), (3, .large), (19, .large), (20, .major)] {
                XCTAssertEqual(QuotaChange(deltas: ["test": sign * points]).intensity, tier)
            }
        }
        XCTAssertEqual(QuotaSoundTheme.handpanName(for: QuotaChange(deltas: ["test": 20])), "03-recovery-lift")
        XCTAssertEqual(QuotaSoundTheme.handpanName(for: QuotaChange(deltas: ["test": -20])), "02-medium-dialogue")
    }
    func testBundledApprovedSoundsDecode() throws {
        for (name, duration) in [("01-small-dialogue", 2.65), ("02-medium-dialogue", 3.2), ("03-recovery-lift", 4.0)] {
            let data = try XCTUnwrap(QuotaSoundTheme.handpanData(named: name))
            let sound = try XCTUnwrap(NSSound(data: data))
            XCTAssertEqual(sound.duration, duration, accuracy: 0.01)
        }
    }
}
