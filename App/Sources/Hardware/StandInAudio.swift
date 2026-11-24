import AVFoundation
import ScrivnerCore

/// A recorder for where there is no microphone to use yet: the simulator, the UI walkthrough, and
/// this stage of the app. It writes a real audio file of silence, as long as the time it "recorded",
/// so everything downstream (the page, the folder, the checker) handles a real file.
/// Stage 1c replaces it with the microphone.
final class StandInAudio: AudioRecording {
    struct CouldNotWrite: Error {}

    private var url: URL?
    private var startedAt: TimeInterval = 0

    func start(writingTo url: URL) throws -> Moment? {
        // A short file at once, so a session that is cut off still has audio to find.
        try Self.writeSilence(seconds: 0.2, to: url)
        self.url = url
        startedAt = ProcessInfo.processInfo.systemUptime
        return nil      // a stand-in has no first sound to time; "now" is used
    }

    func stop() -> Int? {
        guard let url else { return nil }
        self.url = nil
        let seconds = max(0.2, ProcessInfo.processInfo.systemUptime - startedAt)
        do {
            try Self.writeSilence(seconds: seconds, to: url)
        } catch {
            return nil
        }
        return Self.length(of: url)
    }

    /// An audio file's own length in milliseconds, or nil if it cannot be read.
    static func length(of url: URL) -> Int? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Int((Double(file.length) / file.fileFormat.sampleRate * 1000).rounded())
    }

    private static func writeSilence(seconds: Double, to url: URL) throws {
        let sampleRate = 16_000.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000,
        ]
        try? FileManager.default.removeItem(at: url)
        // The file is finished off when `file` goes out of scope at the end of this function.
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let chunk: AVAudioFrameCount = 16_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
            throw CouldNotWrite()
        }
        var remaining = AVAudioFrameCount(max(1, seconds * sampleRate))
        while remaining > 0 {
            let frames = min(chunk, remaining)
            buffer.frameLength = frames
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    memset(channels[channel], 0, Int(frames) * MemoryLayout<Float>.size)
                }
            }
            try file.write(from: buffer)
            remaining -= frames
        }
    }
}
