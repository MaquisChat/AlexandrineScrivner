import Foundation

/// Whether a session has been shared, and whether it has changed since.
public enum ExportState: Equatable, Sendable {
    case never
    case exported(Instant)
    case changedSince(Instant)
}

/// When each session was last shared. Kept in one file beside the sessions, never inside a
/// session's own folder, so a session folder holds nothing but the session.
public struct ExportRecord: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        var at: Instant
        var sha256: String
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// A missing or damaged file is an empty record: the worst that happens is a session shown as not yet shared.
    public static func load(from url: URL) -> ExportRecord {
        var record = ExportRecord()
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
              let root = try? JSONValue.parse(text), case .object(let exports)? = root["exports"] else { return record }
        for (id, value) in exports {
            guard case .string(let atText)? = value["at"], let at = Instant(iso: atText),
                  case .string(let sum)? = value["sha256"], SHA256Hex.isValid(sum) else { continue }
            record.entries[id] = Entry(at: at, sha256: sum)
        }
        return record
    }

    public func save(to url: URL) throws {
        let exports = entries.keys.sorted().map { id -> (key: String, value: JSONValue) in
            (id, .object([("at", .string(entries[id]!.at.iso)), ("sha256", .string(entries[id]!.sha256))]))
        }
        let root = JSONValue.object([("version", .int(1)), ("exports", .object(exports))])
        try Data(root.written().utf8).write(to: url, options: .atomic)
    }

    /// Remembers that the session, as its `session.json` stands now, was shared at `instant`.
    public mutating func noteExport(of manifest: Manifest, sessionJSON: Data, at instant: Instant) {
        entries[manifest.id] = Entry(at: instant, sha256: SHA256Hex.of(sessionJSON))
    }

    /// Compares the session's `session.json` with how it stood when it was last shared.
    public func state(for manifest: Manifest, sessionJSON: Data) -> ExportState {
        guard let entry = entries[manifest.id] else { return .never }
        return entry.sha256 == SHA256Hex.of(sessionJSON) ? .exported(entry.at) : .changedSince(entry.at)
    }

    public mutating func forget(sessionId: String) {
        entries[sessionId] = nil
    }
}
