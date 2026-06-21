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
            DeveloperSettingsView()
                .tabItem { Label("Developer", systemImage: "hammer") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 380)
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
                    .onChange(of: launchAtLogin) {
                        LaunchAtLogin.setEnabled(launchAtLogin)
                        launchAtLogin = LaunchAtLogin.isEnabled   // reflect the real status if the change failed
                    }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct DeveloperSettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                TextField("github.com/acme/app", text: $prefs.gitRemoteBase)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Git remote")
            } footer: {
                Text("⌘O on a commit SHA opens it at this remote (…/commit/<sha>). Leave blank to disable.")
            }

            Section {
                TextField("https://acme.atlassian.net/browse/{KEY}", text: $prefs.issueTrackerTemplate)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Issue tracker")
            } footer: {
                Text("⌘O on an issue key (e.g. ABC-123) opens this URL with {KEY} replaced. Must contain {KEY}.")
            }

            Section {
                Picker("Open file:line in", selection: $prefs.editorKind) {
                    Text("Finder (default)").tag("")
                    ForEach(ClipAction.DevConfig.Editor.allCases, id: \.rawValue) { editor in
                        Text(editor.displayName).tag(editor.rawValue)
                    }
                }
            } header: {
                Text("Editor")
            } footer: {
                Text("⌘O on a file path or a stack-trace file:line opens it here; otherwise Finder reveals the file.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PrivacySettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle("Pause recording", isOn: $prefs.isPaused)
            } footer: {
                Text("While paused, Mimer records nothing new.")
            }

            Section {
                Toggle("Mask detected secrets", isOn: $prefs.maskSecrets)
            } footer: {
                Text("Hides API keys, tokens, and private keys in the list (shown as “API key ••••1234”). They're still stored locally and pasted in full — only the on-screen display is masked.")
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

            Section {
                Button("Clear History…", role: .destructive) { showClearConfirm = true }
                    .confirmationDialog("Clear all clipboard history?", isPresented: $showClearConfirm) {
                        Button("Clear History", role: .destructive) { ClipStore.shared.clearHistory() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Removes your recent clips. Favorites and snippets are kept.")
                    }
            } footer: {
                Text("History is stored locally and unencrypted under Application Support; clearing removes recent clips immediately.")
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

private struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Mimer").font(.title.bold())
            Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
            Text("A fast, private, developer-first clipboard manager.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("GitHub", destination: URL(string: "https://github.com/hasanjafri/Mimer")!)
                Link("License", destination: URL(string: "https://github.com/hasanjafri/Mimer/blob/main/LICENSE")!)
            }
            .padding(.top, 4)
            Spacer()
            Text("© 2026 Hasan Jafri · MIT").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
