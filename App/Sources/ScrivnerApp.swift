import ScrivnerCore
import SwiftUI

@main
struct ScrivnerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(model)
                .preferredColorScheme(model.appearanceForWalkthrough)
                .tint(Theme.accent)
        }
    }
}
