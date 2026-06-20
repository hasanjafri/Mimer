import SwiftUI

/// Settings shell. More panes (Privacy / Appearance / About) fill in across Phase 5;
/// opened via `SettingsLink` from the menu bar.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 280)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Stepper(value: $prefs.historyLimit, in: 25...1000, step: 25) {
                    Text("Keep up to **\(prefs.historyLimit)** clips")
                }
                Stepper(value: $prefs.visibleRows, in: 5...40) {
                    Text("Show **\(prefs.visibleRows)** at once, then scroll")
                }
            } header: {
                Text("History")
            } footer: {
                Text("The menu grows to fit your clips up to this many rows (capped at screen height), then scrolls.")
            }

            Section {
                Toggle("Launch Mimer at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLogin.setEnabled(launchAtLogin) }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
