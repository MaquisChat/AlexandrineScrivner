import AVFoundation
import Foundation

enum ClipMuxError: Error, CustomStringConvertible {
    case missingTrack(String)
    case cannotBuild(String)

    var description: String {
        switch self {
        case .missingTrack(let what): return "no \(what) track"
        case .cannotBuild(let what): return "could not \(what)"
        }
    }
}

/// Makes a copy of a silent clip with a stretch of the session audio as its sound.
enum ClipMuxer {
    static func mux(clip: URL, sessionAudio: URL, audioStartSeconds: Double,
                    durationSeconds: Double, output: URL) async throws {
        let video = AVURLAsset(url: clip)
        let audio = AVURLAsset(url: sessionAudio)

        guard let videoTrack = try await video.loadTracks(withMediaType: .video).first else {
            throw ClipMuxError.missingTrack("video")
        }
        guard let audioTrack = try await audio.loadTracks(withMediaType: .audio).first else {
            throw ClipMuxError.missingTrack("audio")
        }

        let composition = AVMutableComposition()
        guard let videoOut = composition.addMutableTrack(withMediaType: .video,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioOut = composition.addMutableTrack(withMediaType: .audio,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipMuxError.cannotBuild("add tracks to the composition")
        }

        let videoDuration = try await video.load(.duration)
        try videoOut.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        videoOut.preferredTransform = try await videoTrack.load(.preferredTransform)

        let audioStart = CMTime(seconds: audioStartSeconds, preferredTimescale: 48_000)
        let audioLength = CMTime(seconds: durationSeconds, preferredTimescale: 48_000)
        let wanted = CMTimeRange(start: audioStart, duration: audioLength)
        // While the session audio is still being written, the file may not yet reach the clip's end.
        // Inserting a range past what is readable would give a clip whose sound is cut off, silently.
        let readable = try await audioTrack.load(.timeRange)
        guard readable.containsTimeRange(wanted) else {
            throw ClipMuxError.cannotBuild("read the session audio as far as the clip's end")
        }
        try audioOut.insertTimeRange(wanted, of: audioTrack, at: .zero)

        try? FileManager.default.removeItem(at: output)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipMuxError.cannotBuild("create the export")
        }
        try await export.export(to: output, as: .mov)
    }
}
