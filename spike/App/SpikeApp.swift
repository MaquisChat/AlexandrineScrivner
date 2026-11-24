import AVFoundation
import SpikeKit
import SwiftUI

@main
struct SpikeApp: App {
    init() {
        LaunchRecovery.run()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                AudioTestView()
                    .tabItem { Label("Audio test", systemImage: "waveform") }
                StylusProbeView()
                    .tabItem { Label("Stylus", systemImage: "pencil.tip") }
                ReportsView()
                    .tabItem { Label("Reports", systemImage: "doc.text") }
            }
        }
    }
}

/// A run with neither a "finished" marker nor a report was cut off (a crash or a force-quit).
/// Say how much of its audio can still be read, then write its report from what is on disk.
/// A run that finished cleanly but was closed before its report was written just gets its report.
enum LaunchRecovery {
    static func run() {
        let fileManager = FileManager.default
        for run in RunStore.all() {
            if fileManager.fileExists(atPath: run.report.path) { continue }
            if fileManager.fileExists(atPath: run.finishedMarker.path) {
                _ = try? RunStore.writeReport(for: run, title: run.id)
                continue
            }

            let readable: String
            if let file = try? AVAudioFile(forReading: run.audio), file.fileFormat.sampleRate > 0 {
                readable = String(format: "%.1f", Double(file.length) / file.fileFormat.sampleRate)
            } else {
                readable = "unreadable"
            }

            let event = SpikeEvent(hostSeconds: HostClock.now(), wall: Date(),
                                   kind: "recovered-at-launch", detail: "readable-seconds=\(readable)")
            if let line = try? JSONLines.encodeLine(event) {
                RunStore.appendLine(line, to: run.events)
            }
            _ = try? RunStore.writeReport(for: run, title: run.id)
        }
    }
}
