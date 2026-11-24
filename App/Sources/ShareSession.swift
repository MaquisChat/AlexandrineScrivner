import SwiftUI
import UIKit

/// Makes the one file a session is shared as.
enum ShareSession {
    struct CouldNotZip: Error {}

    /// A zip of the session's folder, made by the system and put in a temporary place.
    static func zip(of folder: URL) throws -> URL {
        var result: URL?
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            // The system's zip only lasts as long as this block, so it is copied out.
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(folder.lastPathComponent + ".zip")
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: zipped, to: target)
                result = target
            } catch {
                failure = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
        guard let result else { throw CouldNotZip() }
        return result
    }
}

/// A zip that is ready to share.
struct SharedZip: Identifiable {
    let id = UUID()
    let url: URL
    let sessionId: String
}

/// The system's share sheet. `onDone` says whether the owner went through with it.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onDone: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onDone(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
