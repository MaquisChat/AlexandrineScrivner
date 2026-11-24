import SwiftUI

/// The few settings the app has.
struct SettingsView: View {
    @AppStorage("locationOnForNewSessions") private var locationOn = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Record where photos are taken", isOn: $locationOn)
                        .accessibilityIdentifier("location-default")
                } footer: {
                    Text("This is how each new session starts. For sensitive work, turn it off before starting a session, so that nothing is located at all. It can also be switched during a session, from then on.")
                }
                Section {
                    LabeledContent("Version", value: ThisDevice.appVersion)
                } footer: {
                    Text("Sessions are kept in this app's own folder, which you can see in the Files app. The app never connects to the internet.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings-done")
                }
            }
        }
    }
}
