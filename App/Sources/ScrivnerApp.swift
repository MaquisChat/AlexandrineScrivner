import ScrivnerCore
import SwiftUI

@main
struct ScrivnerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(model)
                .tint(Theme.accent)
        }
    }
}
