import AVFoundation
import SpikeKit
import SwiftUI

/// The controls for one test run: pick a label, start, use the camera, stop.
/// The report is written when the run ends, after any clip sound has been added.
struct AudioTestView: View {
    @StateObject private var audio = AudioRunner()
    @StateObject private var camera = CameraController()

    @State private var label = "R1"
    @State private var run: RunFolder?
    @State private var message: String?
    @State private var failWrites = false
    @State private var finishing = false

    @State private var cameraOn = false
    @State private var quietShutter = false
    @State private var clipSound: ClipSound = .muxAfter
    @State private var waitingClips: [FinishedClip] = []

    private let labels = (1...12).map { "R\($0)" }
    private let micOffMessage = "Microphone access is off. Turn it on in Settings, Privacy & Security, Microphone."

    /// A silent clip whose sound could not be added while the run was still going.
    private struct FinishedClip {
        let url: URL
        let startHostSeconds: Double
        let durationSeconds: Double
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Run") {
                    Picker("Run", selection: $label) {
                        ForEach(labels, id: \.self) { Text($0) }
                    }
                    .disabled(audio.isRunning || finishing)
                    Toggle("Fail writes after 10 s (test)", isOn: $failWrites)
                        .disabled(audio.isRunning || finishing)
                }

                Section("Recording") {
                    LabeledContent("Recorded", value: String(format: "%.1f s", audio.recordedSeconds))
                    if audio.isRunning {
                        Button("Stop", role: .destructive) { audio.stop() }
                    } else {
                        Button("Start") { Task { await start() } }
                            .disabled(finishing)
                    }
                    if finishing {
                        Text("Finishing the run…").foregroundStyle(.secondary)
                    }
                    if let problem = audio.lastProblem {
                        Text(problem).foregroundStyle(.red)
                    }
                    if let message {
                        Text(message).foregroundStyle(.red)
                    }
                }

                Section("Camera") {
                    Toggle("Camera", isOn: $cameraOn)
                    if camera.isOpen {
                        CameraPreview(session: camera.session)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Toggle("Quiet shutter", isOn: $quietShutter)
                    Picker("Clip sound", selection: $clipSound) {
                        ForEach(ClipSound.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .disabled(camera.isRecordingClip)
                    Button("Photo") {
                        if let run { camera.takePhoto(into: run, quietShutter: quietShutter) }
                    }
                    .disabled(!camera.isOpen)
                    Button(camera.isRecordingClip ? "Stop clip" : "Clip") {
                        if camera.isRecordingClip {
                            camera.stopClip()
                        } else if let run {
                            camera.startClip(into: run, sound: clipSound)
                        }
                    }
                    .disabled(!camera.isOpen)
                }
                .disabled(!audio.isRunning)
            }
            .navigationTitle("Audio test")
            .onAppear {
                camera.onClipFinished = { url, start, duration, sound in
                    clipFinished(url: url, start: start, duration: duration, sound: sound)
                }
            }
            .onChange(of: cameraOn) { _, on in
                if on, let log = audio.log, audio.isRunning {
                    camera.open(log: log)
                } else if !on, camera.isOpen {
                    camera.close()
                }
            }
            .onChange(of: audio.isRunning) { _, running in
                if !running { Task { await finishRun() } }
            }
        }
    }

    // MARK: - Starting and finishing

    private func start() async {
        message = nil
        guard await AudioRunner.micAllowed() else {
            message = micOffMessage
            return
        }
        var created: RunFolder?
        do {
            let newRun = try RunStore.create(label: label)
            created = newRun
            audio.failWritesAfterSeconds = failWrites ? 10 : nil
            try await audio.start(in: newRun)
            waitingClips = []
            run = newRun
        } catch MicError.denied {
            if let created { try? FileManager.default.removeItem(at: created.url) }
            message = micOffMessage
        } catch {
            if let created { try? FileManager.default.removeItem(at: created.url) }
            message = "Could not start: \(error.localizedDescription)"
        }
    }

    /// Runs whenever recording ends, whether by the Stop button or by a failure.
    private func finishRun() async {
        guard let finished = run, !finishing else { return }
        finishing = true
        defer { finishing = false }

        // Let a clip that is still recording end, then shut the camera.
        if camera.isRecordingClip {
            camera.stopClip()
            for _ in 0..<30 where camera.isRecordingClip {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        if camera.isOpen {
            camera.close()
        }
        cameraOn = false
        // Give the last clip's callback a moment to arrive.
        try? await Task.sleep(nanoseconds: 300_000_000)

        // The audio file is closed now: add sound to any clip that could not get it during the run.
        let clips = waitingClips
        waitingClips = []
        for clip in clips {
            _ = await addSound(to: clip, in: finished, when: "after-stop")
        }

        run = nil
        do {
            try RunStore.writeReport(for: finished, title: label)
        } catch {
            message = "The report could not be written: \(error.localizedDescription)"
        }
    }

    // MARK: - Clip sound

    private func clipFinished(url: URL, start: Double, duration: Double, sound: ClipSound) {
        guard sound == .muxAfter, let current = run else { return }
        let clip = FinishedClip(url: url, startHostSeconds: start, durationSeconds: duration)
        Task {
            if audio.isRunning {
                // First try while the session audio is still being written.
                let added = await addSound(to: clip, in: current, when: "during-run")
                if !added { waitingClips.append(clip) }
            } else {
                waitingClips.append(clip)
            }
        }
    }

    /// Returns true when the clip needs no further attempt.
    private func addSound(to clip: FinishedClip, in run: RunFolder, when: String) async -> Bool {
        let text = (try? String(contentsOf: run.buffers, encoding: .utf8)) ?? ""
        let buffers = JSONLines.decode(BufferRecord.self, from: text).items
        guard let position = AudioPosition.seconds(atHost: clip.startHostSeconds, buffers: buffers,
                                                   sampleRate: audio.sampleRate) else {
            audio.log?.record("clip-mux-skipped", "no-audio-at-clip-start")
            return true
        }
        let name = clip.url.deletingPathExtension().lastPathComponent + "-muxed.mov"
        let output = clip.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try await ClipMuxer.mux(clip: clip.url, sessionAudio: run.audio, audioStartSeconds: position,
                                    durationSeconds: clip.durationSeconds, output: output)
            audio.log?.record("clip-muxed", String(format: "audio-start=%.3f", position) + " when=\(when)")
            return true
        } catch {
            let kind = when == "during-run" ? "clip-mux-early-failed" : "clip-mux-failed"
            audio.log?.record(kind, String(describing: error))
            return false
        }
    }
}

/// A live view of what the camera sees.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
