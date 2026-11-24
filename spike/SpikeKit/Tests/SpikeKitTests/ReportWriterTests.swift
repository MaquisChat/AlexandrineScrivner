import XCTest
@testable import SpikeKit

final class ReportWriterTests: XCTestCase {
    func testSummaryCountsWallAndRecordedTime() {
        let b = [BufferRecord(sampleTime: 0, frames: 4800, hostSeconds: 10.0),
                 BufferRecord(sampleTime: 52_800, frames: 4800, hostSeconds: 11.1)]
        let s = ReportWriter.summary(buffers: b, sampleRate: 48_000)
        XCTAssertEqual(s.wallSeconds, 1.2, accuracy: 1e-9)
        XCTAssertEqual(s.recordedSeconds, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.gaps.count, 1)
        XCTAssertEqual(s.largestGapSeconds, 1.0, accuracy: 1e-9)
    }

    func testReportTextIsExact() {
        let s = RunSummary(wallSeconds: 181.0, recordedSeconds: 180.0,
                           gaps: [Gap(afterBufferIndex: 650, atHostSeconds: 1065.1, missingSeconds: 1.0, kind: .sampleJump)],
                           largestGapSeconds: 1.0)
        let ev = [SpikeEvent(hostSeconds: 1000.0, wall: Date(timeIntervalSince1970: 0), kind: "audio-start", detail: ""),
                  SpikeEvent(hostSeconds: 1065.0, wall: Date(timeIntervalSince1970: 65), kind: "clip-start", detail: "mux")]
        let t = ReportWriter.text(title: "R5 clip mux", device: "iPhone18,1 iOS 27.1", status: .finished,
                                  summary: s, events: ev, startHostSeconds: 1000.0)
        XCTAssertEqual(t, """
        SPIKE REPORT R5 clip mux
        device: iPhone18,1 iOS 27.1
        status: FINISHED
        wall seconds: 181.0
        recorded seconds: 180.0
        gaps: 1
        largest gap seconds: 1.000
        VERDICT continuous: NO
        EVENTS
        +0.000 audio-start
        +65.000 clip-start mux
        GAPS
        +65.100 sampleJump missing 1.000s near: clip-start(+65.000)

        """)
    }

    func testNoGapsIsContinuousAndListsNone() {
        let s = RunSummary(wallSeconds: 60, recordedSeconds: 60, gaps: [], largestGapSeconds: 0)
        let t = ReportWriter.text(title: "R1", device: "d", status: .finished, summary: s, events: [], startHostSeconds: 0)
        XCTAssertTrue(t.contains("VERDICT continuous: YES\n"))
        XCTAssertTrue(t.contains("EVENTS\n(none)\nGAPS\n(none)\n"))
    }

    func testNoBuffersIsNoAudioNotContinuous() {
        let s = ReportWriter.summary(buffers: [], sampleRate: 48_000)
        XCTAssertEqual(s.recordedSeconds, 0)
        let t = ReportWriter.text(title: "R1", device: "d", status: .finished, summary: s, events: [], startHostSeconds: 0)
        XCTAssertTrue(t.contains("VERDICT continuous: NO AUDIO\n"))
    }

    func testUnfinishedStatusIsShown() {
        let s = RunSummary(wallSeconds: 60, recordedSeconds: 60, gaps: [], largestGapSeconds: 0)
        let t = ReportWriter.text(title: "R10", device: "d", status: .unfinished, summary: s, events: [], startHostSeconds: 0)
        XCTAssertTrue(t.contains("status: UNFINISHED\n"))
    }
}
