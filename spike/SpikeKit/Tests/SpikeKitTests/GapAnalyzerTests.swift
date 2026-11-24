import XCTest
@testable import SpikeKit

final class GapAnalyzerTests: XCTestCase {
    let sr = 48_000.0
    func buf(_ sample: Int64, _ host: Double, frames: Int = 4800) -> BufferRecord {
        BufferRecord(sampleTime: sample, frames: frames, hostSeconds: host)
    }

    func testContiguousBuffersHaveNoGaps() {
        XCTAssertEqual(GapAnalyzer.gaps(in: [buf(0, 10.0), buf(4800, 10.1), buf(9600, 10.2)], sampleRate: sr), [])
    }
    func testSampleJumpIsReportedWithMissingTime() {
        let g = GapAnalyzer.gaps(in: [buf(0, 10.0), buf(52_800, 11.1)], sampleRate: sr)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].kind, .sampleJump)
        XCTAssertEqual(g[0].afterBufferIndex, 0)
        XCTAssertEqual(g[0].atHostSeconds, 10.1, accuracy: 1e-9)
        XCTAssertEqual(g[0].missingSeconds, 1.0, accuracy: 1e-9)
    }
    func testHostJumpWithContinuousSamplesIsReported() {
        let g = GapAnalyzer.gaps(in: [buf(0, 10.0), buf(4800, 12.6)], sampleRate: sr)
        XCTAssertEqual(g.map(\.kind), [.hostJump])
        XCTAssertEqual(g[0].missingSeconds, 2.5, accuracy: 1e-9)
    }
    func testEngineRestartIsARestartNotANegativeGap() {
        let g = GapAnalyzer.gaps(in: [buf(96_000, 10.0), buf(0, 13.1)], sampleRate: sr)
        XCTAssertEqual(g.map(\.kind), [.restart])
        XCTAssertEqual(g[0].missingSeconds, 3.0, accuracy: 1e-9)
    }
    func testJitterWithinToleranceIsIgnored() {
        XCTAssertEqual(GapAnalyzer.gaps(in: [buf(0, 10.0), buf(4800, 10.105)], sampleRate: sr), [])
    }
    func testPositionInsideSecondBuffer() {
        let p = AudioPosition.seconds(atHost: 10.15, buffers: [buf(0, 10.0), buf(4800, 10.1)], sampleRate: sr)
        XCTAssertEqual(p!, 0.15, accuracy: 1e-9)
    }
    func testPositionAfterAGapCountsOnlyRecordedAudio() {
        let p = AudioPosition.seconds(atHost: 12.65, buffers: [buf(0, 10.0), buf(4800, 12.6)], sampleRate: sr)
        XCTAssertEqual(p!, 0.15, accuracy: 1e-9)
    }
    func testPositionInsideAGapOrBeforeStartIsNil() {
        let b = [buf(0, 10.0), buf(4800, 12.6)]
        XCTAssertNil(AudioPosition.seconds(atHost: 11.0, buffers: b, sampleRate: sr))
        XCTAssertNil(AudioPosition.seconds(atHost: 9.0, buffers: b, sampleRate: sr))
    }
}
