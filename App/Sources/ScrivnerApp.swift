import ScrivnerCore
import SwiftUI

@main
struct ScrivnerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(model)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}
