import SwiftUI

/// The few settings the app has.
struct SettingsView: View {
    @AppStorage("locationOnForNewSessions") private var locationOn = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Record places", isOn: $locationOn)
                        .accessibilityIdentifier("location-default")
                } footer: {
                    Text("When this is on, a session keeps where it started and each photo keeps where it was taken. This is how each new session starts. For sensitive work, turn it off before starting a session, so that nothing is located at all. It can also be switched during a session, which changes only what comes after.")
                }
                Section {
                    LabeledContent("Version", value: ThisDevice.appVersion)
                } footer: {
                    Text("Sessions are kept in this app's own folder, which you can see in the Files app. They are left out of iCloud and computer backups: the only copies are this one and the ones you share. The app never connects to the internet.")
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
