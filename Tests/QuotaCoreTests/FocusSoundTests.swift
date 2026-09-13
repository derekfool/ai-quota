import XCTest
@testable import QuotaCore

final class FocusSoundTests: XCTestCase {
    func pcm(starting: Bool) throws -> [Int16] {
        let data = try XCTUnwrap(FocusSound.waveData(starting: starting))
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .utf8), "WAVE")
        XCTAssertEqual(Array(data[24..<28]), [128, 187, 0, 0]) // 48 kHz
        return stride(from: 44, to: data.count, by: 2).map { Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8) }
    }
    func testApprovedAssetsStayQuietAndDistinct() throws {
        let start = try pcm(starting: true), stop = try pcm(starting: false)
        XCTAssertEqual(start.count, 45600)
        XCTAssertEqual(stop.count, 31200)
        for values in [start, stop] {
            let peak = values.map { abs(Int($0)) }.max()!
            XCTAssertGreaterThan(peak, 1000)
            XCTAssertLessThan(peak, 6600)
            XCTAssertEqual(values.last, 0)
        }
    }
    func testStartRepeatsIdenticalTickAt150Milliseconds() throws {
        let values = try pcm(starting: true)
        let tick = Array(values[4800..<12000])
        XCTAssertEqual(tick, Array(values[12000..<19200]))
        XCTAssertEqual(tick, Array(values[19200..<26400]))
        XCTAssertGreaterThan(tick.map { abs(Int($0)) }.max()!, 1000)
    }
}
