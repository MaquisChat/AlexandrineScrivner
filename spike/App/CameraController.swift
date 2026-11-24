import AVFoundation
import Foundation
import SpikeKit

/// How a clip gets its sound.
enum ClipSound: String, CaseIterable {
    /// The clip is recorded silent; the session audio is added to a copy afterwards.
    case muxAfter = "mux"
    /// The capture session takes the microphone as an input of its own for the clip.
    case sessionMic = "session-mic"
}

/// A video-only capture session for photos and clips. It never configures the app's audio session.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isOpen = false
    @Published private(set) var isRecordingClip = false

    /// Called on the main thread when a clip file is complete: the file, the monotonic time its
    /// first frame was captured, its length in seconds, and how it was recorded.
    var onClipFinished: ((URL, Double, Double, ClipSound) -> Void)?

    private let queue = DispatchQueue(label: "spike.camera")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var audioInput: AVCaptureDeviceInput?
    private var log: EventLog?
    private var configured = false
    private var observers: [NSObjectProtocol] = []

    private var clipCount = 0
    private var photoCount = 0
    private var currentSound: ClipSound = .muxAfter
    private var clipStartFromPTS: Double?
    private var clipStartFromCallback: Double?
    private var photoSavers: [Int64: PhotoSaver] = [:]

    func open(log: EventLog) {
        self.log = log
        log.record("camera-open")
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                log.record("camera-runtime-error", "camera access is off")
                return
            }
            self.queue.async {
                self.configureIfNeeded()
                self.session.startRunning()
                log.record("camera-ready")
                DispatchQueue.main.async { self.isOpen = true }
            }
        }
    }

    func close() {
        log?.record("camera-close")
        queue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isOpen = false }
        }
    }

    func takePhoto(into run: RunFolder, quietShutter: Bool) {
        queue.async {
            self.photoCount += 1
            let number = self.photoCount

            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }

            var detail = quietShutter ? "quiet" : "normal"
            if quietShutter {
                if self.photoOutput.isShutterSoundSuppressionSupported {
                    settings.isShutterSoundSuppressionEnabled = true
                } else {
                    detail += " suppression-unsupported"
                }
            }

            let url = run.photos.appendingPathComponent("photo-\(number).heic")
            let identifier = settings.uniqueID
            let saver = PhotoSaver(url: url, log: self.log) { [weak self] in
                self?.queue.async { self?.photoSavers[identifier] = nil }
            }
            self.photoSavers[identifier] = saver
            self.log?.record("photo", detail)
            self.photoOutput.capturePhoto(with: settings, delegate: saver)
        }
    }

    func startClip(into run: RunFolder, sound: ClipSound) {
        queue.async {
            guard !self.movieOutput.isRecording else { return }
            self.clipCount += 1
            self.currentSound = sound
            self.clipStartFromPTS = nil
            self.clipStartFromCallback = nil
            if sound == .sessionMic {
                self.addAudioInput()
            }
            let url = run.clips.appendingPathComponent("clip-\(self.clipCount).mov")
            self.log?.record("clip-start", sound.rawValue)
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecordingClip = true }
        }
    }

    func stopClip() {
        queue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    // MARK: - Session setup (on `queue`)

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = .high
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        } else {
            log?.record("camera-runtime-error", "no back camera input")
        }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                            object: session, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? 0
            self?.log?.record("camera-interrupted", CameraController.name(of: AVCaptureSession.InterruptionReason(rawValue: raw), raw: raw))
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                                            object: session, queue: nil) { [weak self] _ in
            self?.log?.record("camera-interruption-ended")
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                            object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.log?.record("camera-runtime-error", error?.localizedDescription ?? "unknown")
        })
    }

    private func addAudioInput() {
        guard audioInput == nil,
              let microphone = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: microphone) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        } else {
            log?.record("camera-runtime-error", "could not add the microphone input")
        }
        session.commitConfiguration()
    }

    private func removeAudioInput() {
        guard let input = audioInput else { return }
        session.beginConfiguration()
        session.removeInput(input)
        session.commitConfiguration()
        audioInput = nil
    }

    private static func name(of reason: AVCaptureSession.InterruptionReason?, raw: Int) -> String {
        guard let reason else { return "unknown-\(raw)" }
        switch reason {
        case .videoDeviceNotAvailableInBackground: return "video-device-not-available-in-background"
        case .audioDeviceInUseByAnotherClient: return "audio-device-in-use-by-another-client"
        case .videoDeviceInUseByAnotherClient: return "video-device-in-use-by-another-client"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "video-device-not-available-with-multiple-foreground-apps"
        case .videoDeviceNotAvailableDueToSystemPressure: return "video-device-not-available-due-to-system-pressure"
        @unknown default: return "unknown-\(raw)"
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    /// Preferred: the system says exactly when the first frame was captured.
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    startPTS: CMTime, from connections: [AVCaptureConnection]) {
        let hostClock = CMClockGetHostTimeClock()
        let sessionClock = session.synchronizationClock ?? hostClock
        let onHostClock = CMSyncConvertTime(startPTS, from: sessionClock, to: hostClock)
        clipStartFromPTS = CMTimeGetSeconds(onHostClock)
    }

    /// Fallback: the time this callback ran.
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        clipStartFromCallback = HostClock.now()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let duration = CMTimeGetSeconds(output.recordedDuration)
        let sound = currentSound
        let start = clipStartFromPTS ?? clipStartFromCallback ?? HostClock.now() - duration

        var detail = String(format: "seconds=%.3f", duration)
        detail += clipStartFromPTS != nil ? " start=pts" : " start=callback-time"
        if let error {
            let finishedAnyway = ((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
            detail += finishedAnyway ? " ended-early" : " failed: \(error.localizedDescription)"
        }
        log?.record("clip-stop", detail)

        queue.async {
            if sound == .sessionMic {
                self.removeAudioInput()
            }
        }
        DispatchQueue.main.async {
            self.isRecordingClip = false
            self.onClipFinished?(outputFileURL, start, duration, sound)
        }
    }
}

/// Writes one captured photo to disk, then asks to be released.
private final class PhotoSaver: NSObject, AVCapturePhotoCaptureDelegate {
    private let url: URL
    private let log: EventLog?
    private let done: () -> Void

    init(url: URL, log: EventLog?, done: @escaping () -> Void) {
        self.url = url
        self.log = log
        self.done = done
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            log?.record("camera-runtime-error", "photo failed: \(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            log?.record("camera-runtime-error", "photo had no data")
            return
        }
        do {
            try data.write(to: url)
        } catch {
            log?.record("camera-runtime-error", "photo not saved: \(error.localizedDescription)")
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        done()
    }
}
