import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings shell. More panes (Appearance / About) fill in later;
/// opened via the dedicated AppKit window from the menu bar.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 460, height: 360)
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

private struct PrivacySettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Pause recording", isOn: $prefs.isPaused)
            } footer: {
                Text("While paused, Mimer records nothing new.")
            }

            Section {
                if prefs.excludedBundleIDs.isEmpty {
                    Text("No excluded apps.").foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.excludedBundleIDs.sorted(), id: \.self) { bid in
                        HStack {
                            Text(Self.appName(for: bid))
                            Spacer()
                            Button {
                                prefs.excludedBundleIDs.remove(bid)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Stop excluding this app")
                        }
                    }
                }
                Button("Add App…", action: addApp)
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Mimer won’t record while one of these apps is frontmost. Password managers are always ignored.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier {
            prefs.excludedBundleIDs.insert(bid)
        }
    }

    private static func appName(for bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bid
    }
}
