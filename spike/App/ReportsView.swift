import SwiftUI

/// Lists every run, newest first. Selecting one shows its report with a share button.
struct ReportsView: View {
    @State private var runs: [RunFolder] = []

    var body: some View {
        NavigationStack {
            List(runs) { run in
                NavigationLink(run.id, value: run)
            }
            .overlay {
                if runs.isEmpty {
                    ContentUnavailableView("No reports yet", systemImage: "doc.text")
                }
            }
            .navigationTitle("Reports")
            .navigationDestination(for: RunFolder.self) { run in
                ReportDetailView(run: run)
            }
            .onAppear { runs = RunStore.all() }
            .refreshable { runs = RunStore.all() }
        }
    }
}

struct ReportDetailView: View {
    let run: RunFolder

    private var reportText: String {
        (try? String(contentsOf: run.report, encoding: .utf8)) ?? "No report was written for this run."
    }

    private var hasReport: Bool {
        FileManager.default.fileExists(atPath: run.report.path)
    }

    var body: some View {
        ScrollView {
            Text(reportText)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(run.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if hasReport {
                    ShareLink(item: run.report)
                }
            }
        }
    }
}
