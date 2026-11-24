import PencilKit
import SwiftUI
import UIKit

/// What the touch probe has seen so far.
final class TouchProbe: ObservableObject {
    @Published var pencilTouches = 0
    @Published var fingerTouches = 0
    @Published var maxWhilePencilDown = 0
    @Published var maxFingers = 0
    @Published var forceVaried = false

    fileprivate var forcesSeen = Set<Int>()

    func reset() {
        pencilTouches = 0
        fingerTouches = 0
        maxWhilePencilDown = 0
        maxFingers = 0
        forceVaried = false
        forcesSeen.removeAll()
    }
}

/// A plain surface that counts the touches it receives by kind.
final class TouchProbeSurface: UIView {
    var probe: TouchProbe?
    private var active = Set<UITouch>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .secondarySystemBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let probe else { return }
        for touch in touches {
            active.insert(touch)
            if touch.type == .pencil {
                probe.pencilTouches += 1
            } else if touch.type == .direct {
                probe.fingerTouches += 1
            }
        }
        note(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        note(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        active.subtract(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        active.subtract(touches)
    }

    private func note(_ touches: Set<UITouch>) {
        guard let probe else { return }
        for touch in touches where touch.force > 0 {
            probe.forcesSeen.insert(Int((touch.force * 1000).rounded()))
        }
        if probe.forcesSeen.count > 1 {
            probe.forceVaried = true
        }
        let fingers = active.filter { $0.type == .direct }.count
        probe.maxFingers = max(probe.maxFingers, fingers)
        if active.contains(where: { $0.type == .pencil }) {
            probe.maxWhilePencilDown = max(probe.maxWhilePencilDown, active.count)
        }
    }
}

struct TouchProbeArea: UIViewRepresentable {
    let probe: TouchProbe

    func makeUIView(context: Context) -> TouchProbeSurface {
        let view = TouchProbeSurface()
        view.probe = probe
        return view
    }

    func updateUIView(_ uiView: TouchProbeSurface, context: Context) {}
}

/// A drawing canvas whose input rule can be switched between pencil only and any input.
struct DrawingArea: UIViewRepresentable {
    let pencilOnly: Bool
    let clearCount: Int

    final class Coordinator {
        var lastClearCount = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvas.backgroundColor = .secondarySystemBackground
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if context.coordinator.lastClearCount != clearCount {
            context.coordinator.lastClearCount = clearCount
            canvas.drawing = PKDrawing()
        }
    }
}

/// Finds out how this iPad treats the owner's stylus, and saves the answer as run S1.
struct StylusProbeView: View {
    @StateObject private var probe = TouchProbe()

    @State private var pencilOnly = true
    @State private var clearCount = 0
    @State private var drawsInPencilOnly = Answer.notAnswered
    @State private var palmLeavesMarks = Answer.notAnswered
    @State private var savedMessage: String?

    enum Answer: String, CaseIterable {
        case yes = "YES"
        case no = "NO"
        case notAnswered = "NOT ANSWERED"

        var title: String {
            switch self {
            case .yes: return "Yes"
            case .no: return "No"
            case .notAnswered: return "Not answered"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Touch here with a finger, then with the stylus")
                    .font(.headline)
                TouchProbeArea(probe: probe)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Pencil touches: \(probe.pencilTouches)   Finger touches: \(probe.fingerTouches)   Most at once with pencil down: \(probe.maxWhilePencilDown)   Most fingers at once: \(probe.maxFingers)   Force varied: \(probe.forceVaried ? "yes" : "no")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Picker("Drawing mode", selection: $pencilOnly) {
                        Text("Pencil only").tag(true)
                        Text("Any input").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Button("Clear") { clearCount += 1 }
                }
                Text("Rest your hand on the screen and write a sentence here")
                    .font(.headline)
                DrawingArea(pencilOnly: pencilOnly, clearCount: clearCount)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("Does the stylus draw in Pencil only mode?", selection: $drawsInPencilOnly) {
                    ForEach(Answer.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Does a resting hand leave marks in Any input mode?", selection: $palmLeavesMarks) {
                    ForEach(Answer.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                HStack {
                    Button("Save stylus report") { save() }
                        .buttonStyle(.borderedProminent)
                    Button("Reset counts") { probe.reset() }
                    if let savedMessage {
                        Text(savedMessage).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .navigationTitle("Stylus")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func save() {
        let lines = [
            "STYLUS REPORT",
            "device: \(RunStore.deviceLine())",
            "pencil touches: \(probe.pencilTouches)",
            "finger touches: \(probe.fingerTouches)",
            "max simultaneous touches while a pencil touch was down: \(probe.maxWhilePencilDown)",
            "max simultaneous finger touches: \(probe.maxFingers)",
            "force varied: \(probe.forceVaried ? "YES" : "NO")",
            "stylus draws in pencil-only mode: \(drawsInPencilOnly.rawValue)",
            "resting palm leaves marks in any-input mode: \(palmLeavesMarks.rawValue)",
        ]
        do {
            let run = try RunStore.create(label: "S1")
            try (lines.joined(separator: "\n") + "\n").write(to: run.report, atomically: true, encoding: .utf8)
            FileManager.default.createFile(atPath: run.finishedMarker.path, contents: nil)
            savedMessage = "Saved as \(run.id)"
        } catch {
            savedMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
