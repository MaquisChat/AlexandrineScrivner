// scrivner-check: checks session folders made by the recorder.
//
// Everything that decides what is right or wrong lives in ScrivnerCore, where it is tested.
// This file only reads the command line, runs ExifTool when asked to, and prints.
import Foundation
import ScrivnerCore

#if os(macOS) || os(Linux)

func printToStandardError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// Where ExifTool is: the option, then the EXIFTOOL environment variable, then the PATH.
func findExifTool(_ option: String?) -> String? {
    let fileManager = FileManager.default
    if let chosen = option ?? ProcessInfo.processInfo.environment["EXIFTOOL"], !chosen.isEmpty {
        return fileManager.isExecutableFile(atPath: chosen) ? chosen : nil
    }
    for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let candidate = "\(directory)/exiftool"
        if fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

enum MediaRead {
    case facts([String: MediaFacts])
    case failed(String)
}

/// Runs ExifTool once over a session's media files and returns what each says about itself,
/// keyed by the path it has in `session.json`.
func readMedia(in folder: SessionFolder, paths: [String], exiftool: String) -> MediaRead {
    let present = paths.filter { FileManager.default.fileExists(atPath: folder.url(forRelativePath: $0).path) }
    guard !present.isEmpty else { return .facts([:]) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: exiftool)
    // "./" in front, so a file name can never be taken for an option.
    process.arguments = ExifToolOutput.arguments + present.map { "./" + $0 }
    process.currentDirectoryURL = folder.url
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return .failed("ExifTool could not be started (\(error.localizedDescription))")
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
        return .failed("ExifTool printed nothing")
    }
    do {
        var facts: [String: MediaFacts] = [:]
        for (source, value) in try ExifToolOutput.parse(text) {
            facts[source.hasPrefix("./") ? String(source.dropFirst(2)) : source] = value
        }
        return .facts(facts)
    } catch let problem as ExifToolOutputError {
        return .failed(problem.message)
    } catch {
        return .failed("\(error)")
    }
}

guard let arguments = CheckArguments(Array(CommandLine.arguments.dropFirst())) else {
    printToStandardError(CheckArguments.usage)
    exit(2)
}

// A folder with no session.json of its own, but with session folders inside it, is a folder of sessions.
var sessions: [SessionFolder] = []
for path in arguments.folders {
    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let folder = SessionFolder(url: url)
    let inside = SessionStore.sessions(in: url)
    if FileManager.default.fileExists(atPath: folder.sessionJSON.path) || inside.isEmpty {
        sessions.append(folder)
    } else {
        sessions.append(contentsOf: inside.reversed())   // oldest first
    }
}

let exiftool = arguments.media ? findExifTool(arguments.exiftool) : nil
var problems = 0
var warnings = 0

for session in sessions {
    var (manifest, findings) = SessionCheck.folder(session)
    if arguments.media, let manifest {
        if let exiftool {
            switch readMedia(in: session, paths: MediaCheck.mediaPaths(in: manifest), exiftool: exiftool) {
            case .facts(let facts):
                // A file that is not in the folder has already been reported; say nothing more about it.
                let missing = Set(findings.filter { $0.message.hasPrefix("is listed in session.json but is not in the folder") }.map(\.subject))
                findings += MediaCheck.findings(for: manifest, facts: facts).filter { !missing.contains($0.subject) }
            case .failed(let reason):
                findings.append(CheckFinding(.problem, "media tags", "could not be checked: \(reason)"))
            }
        } else {
            findings.append(CheckFinding(.problem, "media tags",
                                         "could not be checked: ExifTool was not found. Run tools/get-exiftool.sh, then pass its last line with --exiftool."))
        }
    }
    problems += findings.filter { $0.severity == .problem }.count
    warnings += findings.filter { $0.severity == .warning }.count
    // The hint to run again with --media is only for runs that did not ask for it.
    print(CheckReport.render(folderName: session.url.lastPathComponent, findings: findings,
                             mediaChecked: arguments.media), terminator: "")
}

print(CheckReport.verdict(sessions: sessions.count, problems: problems, warnings: warnings))
exit(problems == 0 && !sessions.isEmpty ? 0 : 1)

#else

print("scrivner-check runs on a Mac or on Linux.")
exit(2)

#endif
