import Foundation
@testable import ScrivnerCore

/// A clock the test moves by hand. Host time and wall time advance together unless told otherwise.
final class FakeClock: SessionClock {
    var seconds: Double = 0
    var wallShiftMs: Int64 = 0
    var offset = UTCOffset(string: "+05:45")!
    var zone = "Asia/Kathmandu"
    let start = Instant(iso: "2026-11-23T04:57:10.120Z")!      // 10:42:10 on the local clock

    func now() -> Moment {
        Moment(host: 1000 + seconds, wall: start.adding(milliseconds: Int64(seconds * 1000) + wallShiftMs),
               utcOffset: offset, timeZone: zone)
    }
    func advance(_ by: Double) { seconds += by }
}

/// A recorder that writes a few bytes to each file it is started on.
final class FakeAudio: AudioRecording {
    struct NoMicrophone: Error {}
    var started: [URL] = []
    var isRunning = false
    var failNextStart = false
    /// What `stop` reports as the file's own length. Nil means "cannot be read".
    var lengthOnStop: Int? = 10_000

    func start(writingTo url: URL) throws {
        if failNextStart {
            failNextStart = false
            throw NoMicrophone()
        }
        try Data("audio".utf8).write(to: url)
        started.append(url)
        isRunning = true
    }
    func stop() -> Int? {
        isRunning = false
        return lengthOnStop
    }
}

final class FakeLocation: LocationProviding {
    var latest: LocationFix?
    /// A good fix at the market stall, taken at `instant`.
    func fix(at instant: Instant) {
        latest = LocationFix(lat: 27.7046, lon: 85.3076, alt: 1300, horizontalAccuracyM: 5, verticalAccuracyM: 3, at: instant)
    }
}
