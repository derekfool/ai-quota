import XCTest
@testable import QuotaCore

final class QuotaChimeTests: XCTestCase {
    func testSixChimesHaveSafeLevelsSoftEdgesAndIncreasingProminence() {
        var previousLength = 0
        var previousPeak = 0.0
        for intensity in [ChangeIntensity.small, .large, .major] {
            let up = QuotaChime.samples(intensity: intensity, increasing: true)
            let down = QuotaChime.samples(intensity: intensity, increasing: false)
            XCTAssertNotEqual(up, down)
            for samples in [up, down] {
                XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 0.8 })
                XCTAssertEqual(samples.first!, 0, accuracy: 0.00001)
                XCTAssertEqual(samples.last!, 0, accuracy: 0.00001)
                XCTAssertLessThan(samples.count, QuotaChime.sampleRate * 2)
            }
            let peak = up.map { abs($0) }.max()!
            XCTAssertGreaterThan(up.count, previousLength)
            XCTAssertGreaterThan(peak, previousPeak)
            previousLength = up.count; previousPeak = peak
            let wav = QuotaChime.waveData(intensity: intensity, increasing: true)
            XCTAssertEqual(wav.count, 44 + up.count * 2)
            XCTAssertEqual(String(data: wav.prefix(4), encoding: .utf8), "RIFF")
        }
    }
}
