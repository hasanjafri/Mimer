import SwiftUI

/// Settings shell. Panes (General / Privacy / Appearance / About) fill in across
/// Phase 5; opened via `SettingsLink` from the menu bar.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 260)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("Settings coming soon.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
