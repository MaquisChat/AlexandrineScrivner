import SwiftUI

/// The controls for one test run: pick a label, start, stop. The report is written when the run ends.
struct AudioTestView: View {
    @StateObject private var audio = AudioRunner()

    @State private var label = "R1"
    @State private var run: RunFolder?
    @State private var message: String?
    @State private var failWrites = false

    private let labels = (1...12).map { "R\($0)" }
    private let micOffMessage = "Microphone access is off. Turn it on in Settings, Privacy & Security, Microphone."

    var body: some View {
        NavigationStack {
            Form {
                Section("Run") {
                    Picker("Run", selection: $label) {
                        ForEach(labels, id: \.self) { Text($0) }
                    }
                    .disabled(audio.isRunning)
                    Toggle("Fail writes after 10 s (test)", isOn: $failWrites)
                        .disabled(audio.isRunning)
                }

                Section("Recording") {
                    LabeledContent("Recorded", value: String(format: "%.1f s", audio.recordedSeconds))
                    if audio.isRunning {
                        Button("Stop", role: .destructive) { audio.stop() }
                    } else {
                        Button("Start") { Task { await start() } }
                    }
                    if let problem = audio.lastProblem {
                        Text(problem).foregroundStyle(.red)
                    }
                    if let message {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Audio test")
            .onChange(of: audio.isRunning) { _, running in
                if !running { finishRun() }
            }
        }
    }

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
    private func finishRun() {
        guard let finished = run else { return }
        run = nil
        do {
            try RunStore.writeReport(for: finished, title: label)
        } catch {
            message = "The report could not be written: \(error.localizedDescription)"
        }
    }
}
