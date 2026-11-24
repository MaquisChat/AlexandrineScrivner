import AVFoundation
import Foundation
import SpikeKit
import UIKit

enum MicError: Error {
    case denied
}

private struct SimulatedWriteFailure: Error, CustomStringConvertible {
    var description: String { "simulated write failure (test switch)" }
}

/// Owns the microphone for a run: one audio engine, written to the run's audio.caf, with every
/// buffer's timing logged so gaps can be found afterwards.
final class AudioRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var recordedSeconds: Double = 0
    @Published private(set) var lastProblem: String?

    /// Set by `start`. Every event is also appended to the run's events.jsonl.
    private(set) var log: EventLog?
    private(set) var sampleRate: Double = 48_000
    /// Test switch: when set, writes fail after this much recorded audio.
    var failWritesAfterSeconds: Double?

    private let engine = AVAudioEngine()
    private var observers: [NSObjectProtocol] = []
    private var wantsRunning = false

    // Touched from the audio thread and the main thread; guarded by stateLock.
    private let stateLock = NSLock()
    private var file: AVAudioFile?
    private var run: RunFolder?
    private var framesWritten: Int64 = 0

    /// Asks for microphone access if it has not been decided yet.
    static func micAllowed() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(in run: RunFolder) async throws {
        guard await AudioRunner.micAllowed() else { throw MicError.denied }

        let log = EventLog(clock: { (HostClock.now(), Date()) }, sink: { event in
            if let line = try? JSONLines.encodeLine(event) {
                RunStore.appendLine(line, to: run.events)
            }
        })

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setPrefersNoInterruptionsFromSystemAlerts(true)
        try session.setActive(true)

        let format = engine.inputNode.outputFormat(forBus: 0)
        let newFile = try AVAudioFile(forWriting: run.audio, settings: format.settings)

        stateLock.lock()
        self.file = newFile
        self.run = run
        self.framesWritten = 0
        stateLock.unlock()
        self.sampleRate = format.sampleRate
        self.log = log
        self.wantsRunning = true

        addObservers(log: log)
        installTap(format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            wantsRunning = false
            engine.inputNode.removeTap(onBus: 0)
            removeObservers()
            stateLock.lock()
            self.file = nil
            self.run = nil
            stateLock.unlock()
            throw error
        }
        log.record("audio-start", "rate=\(Int(format.sampleRate)) channels=\(format.channelCount)")

        await MainActor.run {
            self.lastProblem = nil
            self.recordedSeconds = 0
            self.isRunning = true
        }
    }

    /// Stops the run and writes the "finished" marker. Call on the main thread.
    func stop() {
        guard isRunning else { return }
        wantsRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        stateLock.lock()
        let finishedRun = run
        file = nil          // releasing the file closes it
        run = nil
        stateLock.unlock()

        log?.record("audio-stop")
        removeObservers()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let finishedRun {
            FileManager.default.createFile(atPath: finishedRun.finishedMarker.path, contents: nil)
        }
        isRunning = false
    }

    // MARK: - Capture

    private func installTap(format: AVAudioFormat) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.handle(buffer: buffer, time: time)
        }
    }

    /// Called on the engine's tap thread, one buffer at a time.
    private func handle(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        stateLock.lock()
        guard let file, let run else {
            stateLock.unlock()
            return
        }
        let record = BufferRecord(sampleTime: time.sampleTime,
                                  frames: Int(buffer.frameLength),
                                  hostSeconds: AVAudioTime.seconds(forHostTime: time.hostTime))
        do {
            if let limit = failWritesAfterSeconds, Double(framesWritten) / sampleRate >= limit {
                throw SimulatedWriteFailure()
            }
            try file.write(from: buffer)
            framesWritten += Int64(buffer.frameLength)
            let seconds = Double(framesWritten) / sampleRate
            stateLock.unlock()

            if let line = try? JSONLines.encodeLine(record) {
                RunStore.appendLine(line, to: run.buffers)
            }
            DispatchQueue.main.async { self.recordedSeconds = seconds }
        } catch {
            stateLock.unlock()
            log?.record("audio-write-failed", String(describing: error))
            DispatchQueue.main.async {
                self.lastProblem = "Recording stopped: the audio could not be saved (\(error))."
                self.stop()
            }
        }
    }

    // MARK: - Recovery

    /// Tries to get audio flowing again after an interruption or a configuration change.
    private func restartEngine() {
        guard wantsRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                let input = engine.inputNode
                input.removeTap(onBus: 0)
                let format = input.outputFormat(forBus: 0)
                installTap(format: format)
                engine.prepare()
                try engine.start()
                log?.record("engine-restart-ok", "rate=\(Int(format.sampleRate)) channels=\(format.channelCount)")
            } else {
                log?.record("engine-restart-ok", "already-running")
            }
        } catch {
            log?.record("engine-restart-failed", String(describing: error))
        }
    }

    // MARK: - Events

    private func addObservers(log: EventLog) {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, object: Any? = nil, _ body: @escaping (Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main, using: body))
        }

        observe(AVAudioSession.interruptionNotification) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            switch AVAudioSession.InterruptionType(rawValue: raw) {
            case .began:
                log.record("interruption-began")
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
                log.record("interruption-ended", shouldResume ? "should-resume" : "no-resume")
                self?.restartEngine()
            default:
                break
            }
        }
        observe(AVAudioSession.routeChangeNotification) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            log.record("route-change", AudioRunner.name(of: AVAudioSession.RouteChangeReason(rawValue: raw)))
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            log.record("media-services-reset")
            self?.restartEngine()
        }
        observe(.AVAudioEngineConfigurationChange, object: engine) { [weak self] _ in
            log.record("engine-config-change")
            self?.restartEngine()
        }
        observe(UIApplication.didEnterBackgroundNotification) { _ in log.record("did-enter-background") }
        observe(UIApplication.willEnterForegroundNotification) { _ in log.record("will-enter-foreground") }
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification) { _ in
            log.record("protected-data-unavailable")
        }
        observe(UIApplication.protectedDataDidBecomeAvailableNotification) { _ in
            log.record("protected-data-available")
        }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            guard let self, self.wantsRunning, !self.engine.isRunning else { return }
            self.restartEngine()
        }
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private static func name(of reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: return "new-device-available"
        case .oldDeviceUnavailable: return "old-device-unavailable"
        case .categoryChange: return "category-change"
        case .override: return "override"
        case .wakeFromSleep: return "wake-from-sleep"
        case .noSuitableRouteForCategory: return "no-suitable-route"
        case .routeConfigurationChange: return "route-configuration-change"
        default: return "unknown"
        }
    }
}
