import Foundation

/// One thing that happened during a test run, stamped on the monotonic clock.
public struct SpikeEvent: Codable, Equatable, Sendable {
    public let hostSeconds: Double
    public let wall: Date
    public let kind: String
    public let detail: String

    public init(hostSeconds: Double, wall: Date, kind: String, detail: String) {
        self.hostSeconds = hostSeconds
        self.wall = wall
        self.kind = kind
        self.detail = detail
    }
}

/// Collects events in the order they are recorded. Safe to call from any thread.
public final class EventLog: @unchecked Sendable {
    private let clock: () -> (hostSeconds: Double, wall: Date)
    private let sink: ((SpikeEvent) -> Void)?
    private let lock = NSLock()
    private var stored: [SpikeEvent] = []

    public init(clock: @escaping () -> (hostSeconds: Double, wall: Date),
                sink: ((SpikeEvent) -> Void)? = nil) {
        self.clock = clock
        self.sink = sink
    }

    public func record(_ kind: String, _ detail: String = "") {
        lock.lock()
        let now = clock()
        let event = SpikeEvent(hostSeconds: now.hostSeconds, wall: now.wall, kind: kind, detail: detail)
        stored.append(event)
        lock.unlock()
        sink?(event)
    }

    public var events: [SpikeEvent] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
