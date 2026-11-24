import Foundation

/// The kinds of media file a session holds.
public enum MediaKind: Sendable {
    case audio, photo, video, inkPicture, inkData
}

/// One session's folder on disk.
public struct SessionFolder: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var sessionJSON: URL { url.appendingPathComponent("session.json") }
    public var notes: URL { url.appendingPathComponent("notes.md") }

    /// Where a path from `session.json` lives on disk.
    public func url(forRelativePath path: String) -> URL {
        var result = url
        for part in path.split(separator: "/") {
            result.appendPathComponent(String(part))
        }
        return result
    }
}

public enum SessionStoreError: Error, Equatable {
    case folderExists(String)
    case missingFile(String)
    case inconsistent([ManifestProblem])
}

/// Creates, saves, loads and finishes session folders.
public enum SessionStore {
    static let subfolders = ["audio", "photos", "video", "ink"]

    public static func folderName(for manifest: Manifest) -> String {
        Naming.sessionFolderName(createdAt: manifest.createdAt, utcOffset: manifest.utcOffset,
                                 title: manifest.title, sessionId: manifest.id)
    }

    /// Makes the folder and its subfolders under `root`, then saves the manifest into it.
    public static func create(_ manifest: Manifest, in root: URL) throws -> SessionFolder {
        let name = folderName(for: manifest)
        let folder = SessionFolder(url: root.appendingPathComponent(name, isDirectory: true))
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: folder.url.path) else {
            throw SessionStoreError.folderExists(name)
        }
        try fileManager.createDirectory(at: folder.url, withIntermediateDirectories: true)
        for sub in subfolders {
            try fileManager.createDirectory(at: folder.url.appendingPathComponent(sub, isDirectory: true),
                                            withIntermediateDirectories: true)
        }
        try save(manifest, to: folder)
        return folder
    }

    /// Writes `session.json` and `notes.md`. Each is replaced in one step, so a crash mid-save
    /// leaves the previous version, never half a file.
    public static func save(_ manifest: Manifest, to folder: SessionFolder) throws {
        try Data(ManifestCoding.encode(manifest).utf8).write(to: folder.sessionJSON, options: .atomic)
        try Data(NotesMarkdown.render(manifest).utf8).write(to: folder.notes, options: .atomic)
    }

    public static func load(_ folder: SessionFolder) throws -> Manifest {
        try ManifestCoding.decode(try String(contentsOf: folder.sessionJSON, encoding: .utf8))
    }

    /// The next unused file name of a kind, counting what the manifest already lists.
    /// A handwriting picture and its data share a number.
    public static func nextFile(_ kind: MediaKind, ext: String, in manifest: Manifest) -> String {
        let prefix: String
        let digits: Int
        switch kind {
        case .audio: (prefix, digits) = ("audio/audio-", 3)
        case .photo: (prefix, digits) = ("photos/photo-", 4)
        case .video: (prefix, digits) = ("video/clip-", 4)
        case .inkPicture, .inkData: (prefix, digits) = ("ink/ink-", 4)
        }
        var highest = 0
        for path in listedFiles(in: manifest) where path.hasPrefix(prefix) {
            let rest = path.dropFirst(prefix.count)
            let number = rest.prefix { $0.isASCII && $0.isNumber }
            if let value = Int(number) {
                highest = max(highest, value)
            }
        }
        let next = String(highest + 1)
        let padded = String(repeating: "0", count: max(0, digits - next.count)) + next
        return "\(prefix)\(padded).\(ext)"
    }

    /// Hashes every listed file, checks the session is complete and consistent, saves it and
    /// returns it. A listed file that is not on disk, or any inconsistency, is an error.
    public static func finalize(_ manifest: Manifest, in folder: SessionFolder) throws -> Manifest {
        var result = manifest

        func hash(_ path: String) throws -> String {
            let url = folder.url(forRelativePath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SessionStoreError.missingFile(path)
            }
            return try SHA256Hex.ofFile(at: url)
        }

        for index in result.spans.indices {
            result.spans[index].sha256 = try hash(result.spans[index].file)
        }
        for index in result.items.indices {
            switch result.items[index] {
            case .photo(let p, let file, _, let gps):
                result.items[index] = .photo(p, file: file, sha256: try hash(file), gps: gps)
            case .video(let p, let durationMs, let endedBy, let sound, let file, _, let gps):
                result.items[index] = .video(p, durationMs: durationMs, endedBy: endedBy, sound: sound,
                                             file: file, sha256: try hash(file), gps: gps)
            case .ink(let p, let endAt, let file, _, let data, _, let strokes):
                result.items[index] = .ink(p, endAt: endAt, file: file, sha256: try hash(file), data: data,
                                           dataSha256: try hash(data), strokes: strokes)
            case .marker, .text:
                break
            }
        }

        let problems = result.problems(finished: true)
        guard problems.isEmpty else {
            throw SessionStoreError.inconsistent(problems)
        }
        try save(result, to: folder)
        return result
    }

    /// Renames the folder when the title has changed. Does not rewrite `session.json`; save separately.
    public static func renameToMatchTitle(_ folder: SessionFolder, manifest: Manifest) throws -> SessionFolder {
        let wanted = folderName(for: manifest)
        guard folder.url.lastPathComponent != wanted else { return folder }
        let target = folder.url.deletingLastPathComponent().appendingPathComponent(wanted, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw SessionStoreError.folderExists(wanted)
        }
        try FileManager.default.moveItem(at: folder.url, to: target)
        return SessionFolder(url: target)
    }

    /// Every folder under `root` that holds a `session.json`, newest name first.
    public static func sessions(in root: URL) -> [SessionFolder] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("session.json").path) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { SessionFolder(url: $0) }
    }

    /// Every file path the manifest lists.
    static func listedFiles(in manifest: Manifest) -> [String] {
        var files = manifest.spans.map(\.file)
        for item in manifest.items {
            switch item {
            case .photo(_, let file, _, _), .video(_, _, _, _, let file, _, _):
                files.append(file)
            case .ink(_, _, let file, _, let data, _, _):
                files.append(file)
                files.append(data)
            case .marker, .text:
                break
            }
        }
        return files
    }
}
