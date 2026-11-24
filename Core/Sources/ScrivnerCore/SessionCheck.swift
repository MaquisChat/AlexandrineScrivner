import Foundation

/// Checks a session folder against its own `session.json`: that the manifest reads and is
/// consistent, that every listed file is there and matches its checksum, and that nothing else
/// has crept in. What the media files say about themselves is `MediaCheck`'s job.
/// What checking one folder found.
public struct SessionCheckResult: Sendable {
    /// The manifest, when it could be read.
    public let manifest: Manifest?
    /// Everything found wrong, in a steady order.
    public let findings: [CheckFinding]
    /// True when the manifest was read, no span is open and every listed file has its checksum.
    public let isFinished: Bool
}

public enum SessionCheck {
    /// File endings the workbench's device import picks up, whatever `session.json` says.
    static let workbenchImports: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf",
                                                "mov", "mp4", "m4v", "m4a", "wav", "mp3"]

    static let unfinishedMessage = "the session was not finished: it was still recording, was cut off, or its files have no checksums yet. Open it in the app so it can be finished."

    /// The manifest, when it could be read, and everything found wrong, in a steady order.
    public static func folder(_ folder: SessionFolder) -> SessionCheckResult {
        func unread(_ message: String) -> SessionCheckResult {
            SessionCheckResult(manifest: nil, findings: [CheckFinding(.problem, "session.json", message)], isFinished: false)
        }
        var found: [CheckFinding] = []
        let fileManager = FileManager.default

        // 1. session.json is there and is text.
        guard let data = fileManager.contents(atPath: folder.sessionJSON.path) else {
            return unread("is missing")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return unread("is not readable text")
        }

        // 2. It reads, strictly.
        let manifest: Manifest
        do {
            manifest = try ManifestCoding.decode(text)
        } catch let problem as ManifestDecodeError {
            let place = problem.path.isEmpty ? "" : "\(problem.path): "
            return unread(place + problem.message)
        } catch let problem as JSONParseError {
            return unread("is not valid JSON: \(problem.message)")
        } catch {
            return unread("could not be read: \(error)")
        }

        // 3. Finished means no open span and a checksum for every file. An unfinished session gets
        //    one plain finding, not one for every missing checksum.
        let listed = listedFiles(in: manifest)
        let isFinished = !manifest.spans.contains { $0.endedBy == nil } && !listed.contains { $0.sha256 == nil }
        if !isFinished {
            found.append(CheckFinding(.problem, "session.json", unfinishedMessage))
        }

        // 4. The manifest is consistent with itself.
        for problem in manifest.problems(finished: isFinished) {
            found.append(CheckFinding(.problem, "session.json", "\(problem.path) \(problem.message)"))
        }

        // 5. Every listed file is there, is not empty, and matches its checksum.
        //    A path that is not a tidy relative path is never opened; rule 4 has already reported it.
        var listedPaths = Set<String>()
        for file in listed where Manifest.isTidyRelativePath(file.path) {
            guard listedPaths.insert(file.path).inserted else { continue }
            let url = folder.url(forRelativePath: file.path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                found.append(CheckFinding(.problem, file.path, "is listed in session.json but is not in the folder"))
                continue
            }
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            if size == 0 {
                found.append(CheckFinding(.problem, file.path, "is empty"))
                continue
            }
            guard let expected = file.sha256, SHA256Hex.isValid(expected) else { continue }
            guard let actual = try? SHA256Hex.ofFile(at: url) else {
                found.append(CheckFinding(.problem, file.path, "could not be read"))
                continue
            }
            if actual != expected {
                found.append(CheckFinding(.problem, file.path,
                                          "does not match its checksum in session.json: the file has changed or is damaged"))
            }
        }

        // 6. Nothing else is in the folder. What macOS leaves behind is not counted.
        for path in filesOnDisk(under: folder.url) where !listedPaths.contains(path) && path != "session.json" && path != "notes.md" {
            if isMacLitter(path) { continue }
            // The workbench picks media up by its file ending, listed or not.
            let ending = path.split(separator: ".").last.map { $0.lowercased() } ?? ""
            let imported = path.contains(".") && workbenchImports.contains(ending)
            found.append(CheckFinding(.warning, path, "is in the folder but not listed in session.json"
                                      + (imported ? "; the workbench would still import it" : "")))
        }

        // 7. notes.md says what session.json says.
        if let notes = fileManager.contents(atPath: folder.notes.path) {
            if notes != Data(NotesMarkdown.render(manifest).utf8) {
                found.append(CheckFinding(.warning, "notes.md", "is out of date with session.json"))
            }
        } else {
            found.append(CheckFinding(.warning, "notes.md", "is missing"))
        }

        // 8. The folder is named after its start time and title.
        let actualName = folder.url.lastPathComponent
        let expectedName = SessionStore.folderName(for: manifest)
        if actualName != expectedName {
            found.append(CheckFinding(.warning, "folder",
                                      "is named \"\(actualName)\"; its start time and title give \"\(expectedName)\""))
        }

        return SessionCheckResult(manifest: manifest, findings: found, isFinished: isFinished)
    }

    /// The session folders directly under `root`, in name order: every folder that holds a
    /// `session.json`, and every folder that looks like a session but has lost it (an interrupted
    /// copy), so that it is reported and not passed over. A folder looks like a session when it is
    /// named the way the recorder names them or holds one of a session's own subfolders.
    public static func sessionFolders(in root: URL) -> [SessionFolder] {
        let fileManager = FileManager.default
        let names = ((try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        var result: [SessionFolder] = []
        for name in names where !name.hasPrefix(".") {
            let url = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let hasManifest = fileManager.fileExists(atPath: url.appendingPathComponent("session.json").path)
            let hasSessionParts = SessionStore.subfolders.contains { part in
                var partIsDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: url.appendingPathComponent(part).path, isDirectory: &partIsDirectory) && partIsDirectory.boolValue
            }
            if hasManifest || hasSessionParts || looksLikeASessionName(name) {
                result.append(SessionFolder(url: url))
            }
        }
        return result
    }

    /// `2026-11-23 1042 … [455d]`: a date, a time, and four characters in square brackets at the end.
    static func looksLikeASessionName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard bytes.count >= 22 else { return false }
        func digits(_ range: Range<Int>) -> Bool { bytes[range].allSatisfy { $0 >= 48 && $0 <= 57 } }
        guard digits(0..<4), bytes[4] == 45, digits(5..<7), bytes[7] == 45, digits(8..<10), bytes[10] == 32,
              digits(11..<15), bytes[15] == 32 else { return false }
        return bytes[bytes.count - 1] == 93 && bytes[bytes.count - 6] == 91
    }

    /// Every file the manifest lists, with the checksum it gives for it.
    static func listedFiles(in manifest: Manifest) -> [(path: String, sha256: String?)] {
        var files: [(path: String, sha256: String?)] = manifest.spans.map { ($0.file, $0.sha256) }
        for item in manifest.items {
            switch item {
            case .photo(_, let file, let sha256, _), .video(_, _, _, _, let file, let sha256, _):
                files.append((file, sha256))
            case .ink(_, _, let file, let sha256, let data, let dataSha256, _):
                files.append((file, sha256))
                files.append((data, dataSha256))
            case .marker, .text:
                break
            }
        }
        return files
    }

    /// `.DS_Store`, which Finder leaves in folders it has shown, and `._name`, which macOS writes
    /// beside a file on disks that cannot hold its extra attributes. Neither is part of a session;
    /// macOS hides the second kind from programs, so it is ignored everywhere for the same answer on
    /// every system.
    static func isMacLitter(_ path: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return name == ".DS_Store" || name.hasPrefix("._")
    }

    /// Every file under `root`, hidden ones included, as sorted paths relative to it with forward slashes.
    static func filesOnDisk(under root: URL) -> [String] {
        var result: [String] = []
        func walk(_ directory: URL, _ prefix: String) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names {
                let url = directory.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    walk(url, prefix + name + "/")
                } else {
                    result.append(prefix + name)
                }
            }
        }
        walk(root, "")
        return result.sorted()
    }
}
