import SwiftUI

/// The menu-bar dropdown companion. For now a placeholder; in later phases it
/// shows recents + favorites and quick actions (open palette, pause, settings).
struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                Text("Mimer").font(.headline)
            }
            Text("Your clipboard history will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Mimer", systemImage: "power")
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 280)
    }
}
