import Foundation

/// The session checker's words: what it prints for each folder, and its verdict.
/// What happened to the check of what is inside the media files.
public enum MediaStatus: Sendable {
    /// It was done.
    case checked
    /// It was not asked for.
    case notAsked
    /// It was asked for, but the session is not finished, so its files may be half written.
    case skippedUnfinished
    /// It was asked for and could not be done; a finding says why.
    case failed
}

public enum CheckReport {
    /// The lines for one session folder. Problems first, then warnings, each in the order given.
    public static func render(folderName: String, findings: [CheckFinding], media: MediaStatus) -> String {
        var lines = ["Session: \(folderName)"]
        if findings.isEmpty {
            lines.append("  Nothing wrong.")
        }
        for finding in findings where finding.severity == .problem {
            lines.append("  PROBLEM  \(finding.subject): \(finding.message)")
        }
        for finding in findings where finding.severity == .warning {
            lines.append("  warning  \(finding.subject): \(finding.message)")
        }
        switch media {
        case .checked, .failed:
            break
        case .notAsked:
            lines.append("  Media tags were not checked. Run again with --media to check them.")
        case .skippedUnfinished:
            lines.append("  Media tags were not checked, because the session is not finished.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The last line of a run. OK only when at least one session was checked and none has a problem.
    public static func verdict(sessions: Int, problems: Int, warnings: Int) -> String {
        func counted(_ count: Int, _ word: String) -> String {
            "\(count) \(word)\(count == 1 ? "" : "s")"
        }
        let detail = "(\(counted(sessions, "session")), \(counted(problems, "problem")), \(counted(warnings, "warning")))"
        return (sessions > 0 && problems == 0 ? "SESSION CHECK OK " : "SESSION CHECK FAILED ") + detail
    }
}

/// What was asked of `scrivner-check` on its command line.
public struct CheckArguments: Equatable, Sendable {
    public var folders: [String]
    public var media: Bool
    public var exiftool: String?

    public static let usage = """
    Usage: scrivner-check [--media] [--exiftool PATH] FOLDER...

    Checks session folders made by the recorder. FOLDER is one session folder, or a folder of them.

      --media           also check the times and places written inside the audio, photo and
                        video files, using ExifTool
      --exiftool PATH   where ExifTool is, if it is not on the PATH
                        (the EXIFTOOL environment variable works too)

    The last line is SESSION CHECK OK or SESSION CHECK FAILED.
    """

    public init(folders: [String], media: Bool, exiftool: String?) {
        self.folders = folders
        self.media = media
        self.exiftool = exiftool
    }

    /// Nil when the arguments make no sense: no folder, an unknown option, or `--exiftool` with nothing after it.
    public init?(_ arguments: [String]) {
        var folders: [String] = []
        var media = false
        var exiftool: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--media":
                media = true
            case "--exiftool":
                index += 1
                guard index < arguments.count else { return nil }
                exiftool = arguments[index]
            default:
                guard !argument.hasPrefix("-") else { return nil }
                folders.append(argument)
            }
            index += 1
        }
        guard !folders.isEmpty else { return nil }
        self.init(folders: folders, media: media, exiftool: exiftool)
    }
}
