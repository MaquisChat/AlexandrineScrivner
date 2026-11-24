import Foundation

public enum RunStatus: String, Sendable {
    case finished = "FINISHED"
    case unfinished = "UNFINISHED"
}

public struct RunSummary: Equatable, Sendable {
    /// End of the last buffer minus start of the first; 0 with no buffers.
    public let wallSeconds: Double
    /// Total frames divided by the sample rate.
    public let recordedSeconds: Double
    public let gaps: [Gap]
    /// 0 with no gaps.
    public let largestGapSeconds: Double

    public init(wallSeconds: Double, recordedSeconds: Double, gaps: [Gap], largestGapSeconds: Double) {
        self.wallSeconds = wallSeconds
        self.recordedSeconds = recordedSeconds
        self.gaps = gaps
        self.largestGapSeconds = largestGapSeconds
    }
}

public enum ReportWriter {
    public static func summary(buffers: [BufferRecord], sampleRate: Double, toleranceSeconds: Double = 0.010) -> RunSummary {
        guard let first = buffers.first, let last = buffers.last else {
            return RunSummary(wallSeconds: 0, recordedSeconds: 0, gaps: [], largestGapSeconds: 0)
        }
        let totalFrames = buffers.reduce(0) { $0 + $1.frames }
        let lastEnd = last.hostSeconds + Double(last.frames) / sampleRate
        let gaps = GapAnalyzer.gaps(in: buffers, sampleRate: sampleRate, toleranceSeconds: toleranceSeconds)
        return RunSummary(wallSeconds: lastEnd - first.hostSeconds,
                          recordedSeconds: Double(totalFrames) / sampleRate,
                          gaps: gaps,
                          largestGapSeconds: gaps.map(\.missingSeconds).max() ?? 0)
    }

    public static func text(title: String, device: String, status: RunStatus, summary: RunSummary,
                            events: [SpikeEvent], startHostSeconds: Double, nearWindowSeconds: Double = 2.0) -> String {
        func offset(_ hostSeconds: Double) -> String {
            String(format: "%+.3f", hostSeconds - startHostSeconds)
        }

        let verdict: String
        if summary.recordedSeconds == 0 {
            verdict = "NO AUDIO"
        } else if summary.gaps.isEmpty {
            verdict = "YES"
        } else {
            verdict = "NO"
        }

        var lines: [String] = [
            "SPIKE REPORT \(title)",
            "device: \(device)",
            "status: \(status.rawValue)",
            "wall seconds: " + String(format: "%.1f", summary.wallSeconds),
            "recorded seconds: " + String(format: "%.1f", summary.recordedSeconds),
            "gaps: \(summary.gaps.count)",
            "largest gap seconds: " + String(format: "%.3f", summary.largestGapSeconds),
            "VERDICT continuous: \(verdict)",
        ]

        lines.append("EVENTS")
        if events.isEmpty {
            lines.append("(none)")
        }
        for event in events {
            let detail = event.detail.isEmpty ? "" : " \(event.detail)"
            lines.append("\(offset(event.hostSeconds)) \(event.kind)\(detail)")
        }

        lines.append("GAPS")
        if summary.gaps.isEmpty {
            lines.append("(none)")
        }
        for gap in summary.gaps {
            let near = events
                .filter { abs($0.hostSeconds - gap.atHostSeconds) <= nearWindowSeconds }
                .map { "\($0.kind)(\(offset($0.hostSeconds)))" }
            let nearText = near.isEmpty ? "" : " near: " + near.joined(separator: ", ")
            let missing = String(format: "%.3f", gap.missingSeconds)
            lines.append("\(offset(gap.atHostSeconds)) \(gap.kind.rawValue) missing \(missing)s\(nearText)")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
