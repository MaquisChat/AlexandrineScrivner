import AVFoundation
import Foundation
import SpikeKit

/// One test run's folder: Documents/runs/<yyyyMMdd-HHmmss>-<label>/
struct RunFolder: Identifiable, Hashable {
    let url: URL

    var id: String { url.lastPathComponent }
    var audio: URL { url.appendingPathComponent("audio.caf") }
    var buffers: URL { url.appendingPathComponent("buffers.jsonl") }
    var events: URL { url.appendingPathComponent("events.jsonl") }
    var report: URL { url.appendingPathComponent("report.txt") }
    var finishedMarker: URL { url.appendingPathComponent("finished") }
    var clips: URL { url.appendingPathComponent("clips", isDirectory: true) }
    var photos: URL { url.appendingPathComponent("photos", isDirectory: true) }
}

/// The one clock every event uses: monotonic seconds, the same base audio buffers are stamped on.
enum HostClock {
    static func now() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }
}

enum RunStore {
    static func runsRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func create(label: String, now: Date = Date()) throws -> RunFolder {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        let cleaned = String(String.UnicodeScalarView(label.unicodeScalars.filter { allowed.contains($0) }))
        let base = "\(formatter.string(from: now))-\(cleaned.isEmpty ? "run" : cleaned)"

        let fileManager = FileManager.default
        var url = runsRoot().appendingPathComponent(base, isDirectory: true)
        var attempt = 2
        while fileManager.fileExists(atPath: url.path) {
            url = runsRoot().appendingPathComponent("\(base)-\(attempt)", isDirectory: true)
            attempt += 1
        }

        let run = RunFolder(url: url)
        try fileManager.createDirectory(at: run.url, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: run.clips, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: run.photos, withIntermediateDirectories: true)
        return run
    }

    /// Every run folder, newest first.
    static func all() -> [RunFolder] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: runsRoot(), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { RunFolder(url: $0) }
    }

    /// Appends the line and a newline. Each call opens and closes the file, so a crash loses at most one line.
    static func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Builds report.txt from the files on disk and returns its text.
    @discardableResult
    static func writeReport(for run: RunFolder, title: String) throws -> String {
        let bufferText = (try? String(contentsOf: run.buffers, encoding: .utf8)) ?? ""
        let eventText = (try? String(contentsOf: run.events, encoding: .utf8)) ?? ""
        let buffers = JSONLines.decode(BufferRecord.self, from: bufferText)
        let events = JSONLines.decode(SpikeEvent.self, from: eventText)

        let sampleRate = (try? AVAudioFile(forReading: run.audio))?.fileFormat.sampleRate ?? 48_000
        let summary = ReportWriter.summary(buffers: buffers.items, sampleRate: sampleRate)
        let start = buffers.items.first?.hostSeconds ?? events.items.first?.hostSeconds ?? 0
        let finished = FileManager.default.fileExists(atPath: run.finishedMarker.path)

        var text = ReportWriter.text(title: title, device: deviceLine(),
                                     status: finished ? .finished : .unfinished,
                                     summary: summary, events: events.items, startHostSeconds: start)
        text += "log lines skipped: \(buffers.skippedLines + events.skippedLines)\n"
        try text.write(to: run.report, atomically: true, encoding: .utf8)
        return text
    }

    /// Hardware model and OS version, e.g. "iPhone18,1 iOS 27.1". Never the device's own name.
    static func deviceLine() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let model = String(cString: machine)

        let version = ProcessInfo.processInfo.operatingSystemVersion
        var versionText = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion != 0 {
            versionText += ".\(version.patchVersion)"
        }
        let system = model.hasPrefix("iPad") ? "iPadOS" : "iOS"
        return "\(model) \(system) \(versionText)"
    }
}
