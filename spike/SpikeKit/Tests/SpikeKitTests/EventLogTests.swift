import XCTest
@testable import SpikeKit

final class EventLogTests: XCTestCase {
    func testEventsAreStoredInOrderAndSentToTheSink() {
        var t = 100.0
        var sunk: [String] = []
        let log = EventLog(clock: { t += 1; return (t, Date(timeIntervalSince1970: t)) },
                           sink: { sunk.append($0.kind) })
        log.record("audio-start")
        log.record("clip-start", "mux")
        XCTAssertEqual(log.events.map(\.kind), ["audio-start", "clip-start"])
        XCTAssertEqual(log.events[1].detail, "mux")
        XCTAssertEqual(log.events[0].hostSeconds, 101.0)
        XCTAssertEqual(sunk, ["audio-start", "clip-start"])
    }
}
