import Foundation

/// Checks a session folder against its own `session.json`: that the manifest reads and is
/// consistent, that every listed file is there and matches its checksum, and that nothing else
/// has crept in. What the media files say about themselves is `MediaCheck`'s job.
public enum SessionCheck {
    static let unfinishedMessage = "the session was not finished: it was still recording, was cut off, or its files have no checksums yet. Open it in the app so it can be finished."

    /// The manifest, when it could be read, and everything found wrong, in a steady order.
    public static func folder(_ folder: SessionFolder) -> (manifest: Manifest?, findings: [CheckFinding]) {
        var found: [CheckFinding] = []
        let fileManager = FileManager.default

        // 1. session.json is there and is text.
        guard let data = fileManager.contents(atPath: folder.sessionJSON.path) else {
            return (nil, [CheckFinding(.problem, "session.json", "is missing")])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return (nil, [CheckFinding(.problem, "session.json", "is not readable text")])
        }

        // 2. It reads, strictly.
        let manifest: Manifest
        do {
            manifest = try ManifestCoding.decode(text)
        } catch let problem as ManifestDecodeError {
            let place = problem.path.isEmpty ? "" : "\(problem.path): "
            return (nil, [CheckFinding(.problem, "session.json", place + problem.message)])
        } catch let problem as JSONParseError {
            return (nil, [CheckFinding(.problem, "session.json", "is not valid JSON: \(problem.message)")])
        } catch {
            return (nil, [CheckFinding(.problem, "session.json", "could not be read: \(error)")])
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

        // 6. Nothing else is in the folder.
        for path in filesOnDisk(under: folder.url) where !listedPaths.contains(path) && path != "session.json" && path != "notes.md" {
            found.append(CheckFinding(.warning, path, "is in the folder but not listed in session.json"))
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

        return (manifest, found)
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
