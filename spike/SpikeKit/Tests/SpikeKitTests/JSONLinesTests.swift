import XCTest
@testable import SpikeKit

final class JSONLinesTests: XCTestCase {
    func testRoundTrip() throws {
        let a = BufferRecord(sampleTime: 0, frames: 4800, hostSeconds: 10.0)
        let b = BufferRecord(sampleTime: 4800, frames: 4800, hostSeconds: 10.1)
        let text = try [a, b].map(JSONLines.encodeLine).joined(separator: "\n") + "\n"
        let r = JSONLines.decode(BufferRecord.self, from: text)
        XCTAssertEqual(r.items, [a, b])
        XCTAssertEqual(r.skippedLines, 0)
    }
    func testTruncatedLastLineIsSkipped() throws {
        let a = BufferRecord(sampleTime: 0, frames: 4800, hostSeconds: 10.0)
        let text = try JSONLines.encodeLine(a) + "\n{\"sampleTime\":48"
        let r = JSONLines.decode(BufferRecord.self, from: text)
        XCTAssertEqual(r.items, [a])
        XCTAssertEqual(r.skippedLines, 1)
    }
}
