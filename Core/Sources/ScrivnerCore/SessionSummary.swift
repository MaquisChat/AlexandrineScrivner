import Foundation

/// One line of the session list on the home screen.
public struct SessionSummary: Equatable, Sendable, Identifiable {
    public let id: String
    public let folder: SessionFolder
    /// The title to show; an untitled session shows its date and time.
    public let title: String
    public let startedAt: Instant
    public let utcOffset: UTCOffset
    /// The audio recorded so far. A span still being recorded is not counted.
    public let recordedMilliseconds: Int
    public let photoCount: Int
    public let clipCount: Int
    /// No span open and every file has its checksum: ready to share.
    public let isFinished: Bool
    public let export: ExportState

    /// Every session under `root`, newest first. A folder whose `session.json` cannot be read is
    /// named in `unreadable`, never dropped silently: its recordings are still there.
    public static func list(in root: URL, exports: ExportRecord) -> (sessions: [SessionSummary], unreadable: [String]) {
        var sessions: [SessionSummary] = []
        var unreadable: [String] = []
        for folder in SessionStore.sessions(in: root) {
            guard let data = FileManager.default.contents(atPath: folder.sessionJSON.path),
                  let text = String(data: data, encoding: .utf8),
                  let manifest = try? ManifestCoding.decode(text) else {
                unreadable.append(folder.url.lastPathComponent)
                continue
            }
            var photos = 0
            var clips = 0
            for item in manifest.items {
                switch item {
                case .photo: photos += 1
                case .video: clips += 1
                case .marker, .text, .ink: break
                }
            }
            let finished = !manifest.spans.contains { $0.endedBy == nil }
                && !SessionCheck.listedFiles(in: manifest).contains { $0.sha256 == nil }
            sessions.append(SessionSummary(
                id: manifest.id, folder: folder, title: manifest.displayTitle, startedAt: manifest.createdAt,
                utcOffset: manifest.utcOffset,
                recordedMilliseconds: manifest.spans.reduce(0) { $0 + ($1.durationMs ?? 0) },
                photoCount: photos, clipCount: clips, isFinished: finished,
                export: exports.state(for: manifest, sessionJSON: data)))
        }
        sessions.sort { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
        return (sessions, unreadable.sorted())
    }
}

extension SessionStore {
    /// Removes a session's folder and everything in it. This is the only way the app deletes
    /// recordings. A folder that does not hold a `session.json` is refused and left alone.
    public static func delete(_ folder: SessionFolder) throws {
        guard FileManager.default.fileExists(atPath: folder.sessionJSON.path) else {
            throw SessionStoreError.missingFile("session.json")
        }
        try FileManager.default.removeItem(at: folder.url)
    }
}
