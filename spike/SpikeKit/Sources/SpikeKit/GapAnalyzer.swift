import Foundation

/// One audio buffer as the engine delivered it.
public struct BufferRecord: Codable, Equatable, Sendable {
    public let sampleTime: Int64
    public let frames: Int
    public let hostSeconds: Double

    public init(sampleTime: Int64, frames: Int, hostSeconds: Double) {
        self.sampleTime = sampleTime
        self.frames = frames
        self.hostSeconds = hostSeconds
    }
}

public enum GapKind: String, Codable, Sendable {
    /// Sample numbers skipped forward: audio was dropped.
    case sampleJump
    /// Sample numbers are continuous but real time passed with no audio.
    case hostJump
    /// Sample numbering began again: the engine was restarted.
    case restart
}

public struct Gap: Equatable, Sendable {
    public let afterBufferIndex: Int
    public let atHostSeconds: Double
    public let missingSeconds: Double
    public let kind: GapKind

    public init(afterBufferIndex: Int, atHostSeconds: Double, missingSeconds: Double, kind: GapKind) {
        self.afterBufferIndex = afterBufferIndex
        self.atHostSeconds = atHostSeconds
        self.missingSeconds = missingSeconds
        self.kind = kind
    }
}

public enum GapAnalyzer {
    public static func gaps(in buffers: [BufferRecord], sampleRate: Double, toleranceSeconds: Double = 0.010) -> [Gap] {
        var found: [Gap] = []
        guard buffers.count > 1 else { return found }
        for index in 0..<(buffers.count - 1) {
            let a = buffers[index]
            let b = buffers[index + 1]
            let aEnd = a.hostSeconds + Double(a.frames) / sampleRate
            let sampleDelta = b.sampleTime - (a.sampleTime + Int64(a.frames))
            let hostHole = b.hostSeconds - aEnd

            let kind: GapKind
            let missing: Double
            if sampleDelta < 0 {
                kind = .restart
                missing = max(hostHole, 0)
            } else if sampleDelta > 0 {
                kind = .sampleJump
                missing = Double(sampleDelta) / sampleRate
            } else if hostHole > toleranceSeconds {
                kind = .hostJump
                missing = hostHole
            } else {
                continue
            }
            found.append(Gap(afterBufferIndex: index, atHostSeconds: aEnd, missingSeconds: missing, kind: kind))
        }
        return found
    }
}

public enum AudioPosition {
    /// Seconds into the audio file for a monotonic time, or nil if no buffer covers that time.
    public static func seconds(atHost host: Double, buffers: [BufferRecord], sampleRate: Double) -> Double? {
        var framesBefore = 0
        for buffer in buffers {
            let end = buffer.hostSeconds + Double(buffer.frames) / sampleRate
            if host >= buffer.hostSeconds && host < end {
                return Double(framesBefore) / sampleRate + (host - buffer.hostSeconds)
            }
            framesBefore += buffer.frames
        }
        return nil
    }
}
