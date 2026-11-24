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

    guard !data.isEmpty else { return .failed("ExifTool printed nothing") }
    guard let text = String(data: data, encoding: .utf8) else { return .failed("ExifTool's output could not be read as text") }
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

let exiftool = arguments.media ? findExifTool(arguments.exiftool) : nil
var sessionCount = 0
var problems = 0
var warnings = 0

@MainActor
func report(_ name: String, _ findings: [CheckFinding], _ media: MediaStatus) {
    sessionCount += 1
    problems += findings.filter { $0.severity == .problem }.count
    warnings += findings.filter { $0.severity == .warning }.count
    print(CheckReport.render(folderName: name, findings: findings, media: media), terminator: "")
}

@MainActor
func check(_ session: SessionFolder) {
    let result = SessionCheck.folder(session)
    var findings = result.findings
    var media: MediaStatus = arguments.media ? .failed : .notAsked
    if arguments.media, let manifest = result.manifest {
        if !result.isFinished {
            // Files of a session that was cut off may be half written; the one finding above says what to do.
            media = .skippedUnfinished
        } else if let exiftool {
            switch readMedia(in: session, paths: MediaCheck.mediaPaths(in: manifest), exiftool: exiftool) {
            case .facts(let facts):
                // A file that is missing or empty has already been reported; say nothing more about it.
                let alreadyReported = Set(findings.filter {
                    $0.message.hasPrefix("is listed in session.json but is not in the folder") || $0.message == "is empty"
                }.map(\.subject))
                findings += MediaCheck.findings(for: manifest, facts: facts).filter { !alreadyReported.contains($0.subject) }
                media = .checked
            case .failed(let reason):
                findings.append(CheckFinding(.problem, "media tags", "could not be checked: \(reason)"))
            }
        } else {
            findings.append(CheckFinding(.problem, "media tags",
                                         "could not be checked: ExifTool was not found. Run tools/get-exiftool.sh, then pass its last line with --exiftool."))
        }
    }
    report(session.url.lastPathComponent, findings, media)
}

for path in arguments.folders {
    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        report(url.lastPathComponent, [CheckFinding(.problem, "folder", "there is nothing at \(path)")], .failed)
        continue
    }
    guard isDirectory.boolValue else {
        let hint = url.pathExtension.lowercased() == "zip" ? " Open the zip first, then check the folder that comes out of it." : ""
        report(url.lastPathComponent, [CheckFinding(.problem, "folder", "is a file, not a folder.\(hint)")], .failed)
        continue
    }
    let folder = SessionFolder(url: url)
    if FileManager.default.fileExists(atPath: folder.sessionJSON.path) {
        check(folder)
        continue
    }
    // No session.json of its own: a folder of sessions, each checked, including any that has
    // lost its session.json. A folder with no sessions in it is checked as one, and says so.
    let inside = SessionCheck.sessionFolders(in: url)
    if inside.isEmpty {
        check(folder)
    } else {
        inside.forEach(check)
    }
}

print(CheckReport.verdict(sessions: sessionCount, problems: problems, warnings: warnings))
exit(problems == 0 && sessionCount > 0 ? 0 : 1)

#else

print("scrivner-check runs on a Mac or on Linux.")
exit(2)

#endif
